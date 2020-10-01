defmodule Curie.Storage do
  @moduledoc """
  DB utility and member whitelisting.
  """

  use Curie.Commands

  alias Nostrum.Cache.{ChannelCache, GuildCache}
  alias Nostrum.Struct.{Message, User}
  alias Nostrum.Struct.Guild.Member

  alias Curie.Data.{Balance, Details, Status}
  alias Curie.Data

  alias Curie.Heartbeat

  @type presence :: {Guild.id(), old_presence :: map, new_presence :: map}

  @self __MODULE__

  @user_tables [Balance, Details]

  @spec child_spec(any) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{id: @self, start: {@self, :start_link, []}, restart: :transient}
  end

  @spec start_link :: Supervisor.on_start()
  def start_link do
    Task.start_link(&clear_last_status/0)
  end

  @spec clear_last_status :: :ok
  def clear_last_status do
    if Heartbeat.offline_for_more_than?(120) do
      Data.update_all(Details, set: [last_status_change: nil, last_status_type: nil])
    end

    :ok
  end

  @spec whitelisted?(Message.t() | Member.t() | User.id()) :: boolean
  def whitelisted?(%{author: %{id: user_id}}) do
    !!Data.get(Balance, user_id)
  end

  def whitelisted?(%{user: %{id: user_id}}) do
    !!Data.get(Balance, user_id)
  end

  def whitelisted?(user_id) do
    !!Data.get(Balance, user_id)
  end

  @spec whitelist_message(Message.t()) :: :ok
  def whitelist_message(%{guild_id: guild_id} = message) do
    with {:ok, %{owner_id: owner_id}} <- GuildCache.get(guild_id),
         owner_name = Curie.get_display_name(guild_id, owner_id) do
      "Whitelisting required, ask #{owner_name}."
      |> (&Curie.embed(message, &1, "red")).()
    end

    :ok
  end

  @spec remove(User.id()) :: :ok
  def remove(user) do
    for table <- @user_tables do
      with %{} = entry <- Data.get(table, user) do
        Data.delete(entry)
      end
    end

    :ok
  end

  @spec store_details(Message.t() | presence) :: :ok | :pass
  def store_details(%{author: %{id: id}, channel_id: channel_id, guild_id: guild_id, type: type})
      when guild_id != nil do
    with {:ok, %{name: channel_name}} when type == 0 <- ChannelCache.get(channel_id) do
      (Data.get(Details, id) || %Details{member: id})
      |> Details.changeset(%{
        spoke: Timex.to_unix(Timex.now()),
        channel: "#" <> channel_name,
        guild_id: guild_id
      })
      |> Data.insert_or_update()
    end

    :ok
  end

  def store_details({_guild_id, _old, %{user: %{id: id}, status: status}}) do
    details = Data.get(Details, id)

    if details == nil or details.last_status_type != to_string(status) do
      (details || %Details{member: id})
      |> Details.changeset(
        if status == :offline do
          %{
            offline_since: Timex.to_unix(Timex.now()),
            last_status_change: nil,
            last_status_type: nil
          }
        else
          %{
            last_status_change: Timex.to_unix(Timex.now()),
            last_status_type: to_string(status)
          }
        end
      )
      |> Data.insert_or_update()
    end

    :ok
  end

  def store_details(_unusable), do: :pass

  @spec get_details(User.id()) :: Details.t()
  def get_details(member_id) do
    Data.get(Details, member_id) || struct(Details)
  end

  @spec status_gather(presence) :: :ok | :pass
  def status_gather({guild_id, _old, %{game: %{name: game_name, type: 0}, user: %{id: user_id}}}) do
    if !Data.get(Status, game_name) do
      %Status{message: game_name, member: Curie.get_display_name(guild_id, user_id)}
      |> Data.insert()
    end

    :ok
  end

  def status_gather(_unusable), do: :pass

  @spec change_member_standing(String.t(), User.id(), User.username(), Message.t()) :: :ok
  def change_member_standing("whitelist", id, name, %{guild_id: guild} = message)
      when guild != nil do
    if whitelisted?(id) do
      "Member already whitelisted."
      |> (&Curie.embed(message, &1, "red")).()
    else
      %Balance{member: id, value: 0, guild: guild}
      |> Data.insert()

      "#{name} added, wooo! :tada:"
      |> (&Curie.embed(message, &1, "green")).()
    end

    :ok
  end

  def change_member_standing("remove", id, name, message) do
    case Data.get(Balance, id) do
      nil ->
        "Already does not exist. Job's done... I guess?"
        |> (&Curie.embed(message, &1, "red")).()

      balance ->
        Data.delete(balance)

        "#{name} removed, never liked that one anyway."
        |> (&Curie.embed(message, &1, "green")).()
    end

    :ok
  end

  @impl Curie.Commands
  def command({action, @owner = message, _args}) when action in ["whitelist", "remove"] do
    case Curie.get_member(message, 1) do
      {:ok, %{nick: nick, user: %{id: id, username: username}}} ->
        change_member_standing(action, id, nick || username, message)

      {:error, reason} ->
        Curie.embed(message, "Unable to #{action} member (#{reason})", "red")
    end
  end

  @impl Curie.Commands
  def command(_call), do: :pass

  def handler(%{author: %{id: id}} = message) do
    with {:ok, curie_id} when curie_id != id <- Curie.my_id() do
      store_details(message)
    end
  end
end
