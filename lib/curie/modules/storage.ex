defmodule Curie.Storage do
  use Curie.Commands

  alias Nostrum.Cache.{ChannelCache, GuildCache}
  alias Nostrum.Struct.{Channel, Message, User}

  alias Curie.Data.{Balance, Details, Status}
  alias Curie.Data

  @type presence :: {Guild.id(), old_presence :: map(), new_presence :: map()}

  @user_tables [Balance, Details]

  @spec whitelisted?(%{author: %{id: User.id()}}) :: boolean()
  def whitelisted?(%{author: %{id: user}}) do
    !!Data.get(Balance, user)
  end

  @spec whitelisted?(%{user: %{id: User.id()}}) :: boolean()
  def whitelisted?(%{user: %{id: user}}) do
    !!Data.get(Balance, user)
  end

  @spec whitelisted?(User.id()) :: boolean()
  def whitelisted?(user) do
    !!Data.get(Balance, user)
  end

  @spec whitelist_message(map()) :: no_return()
  def whitelist_message(%{guild_id: guild_id} = message) do
    with {:ok, %{owner_id: owner_id}} <- GuildCache.get(guild_id),
         owner_name = Curie.get_display_name(guild_id, owner_id) do
      "Whitelisting required, ask #{owner_name}."
      |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @spec remove(User.id()) :: no_return()
  def remove(user) do
    for table <- @user_tables do
      with %{} = entry <- Data.get(table, user) do
        Data.delete(entry)
      end
    end
  end

  @spec store_details(Message.t()) :: no_return()
  def store_details(%{author: %{id: id}, channel_id: channel_id, type: type}) do
    with {:ok, %Channel{name: name}} when type == 0 <- ChannelCache.get(channel_id) do
      case Data.get(Details, id) do
        nil -> %Details{member: id}
        entry -> entry
      end
      |> Details.changeset(%{
        spoke: Curie.local_datetime() |> Timex.to_unix(),
        channel: if(name, do: "##{name}", else: "#DirectMessage")
      })
      |> Data.insert_or_update()
    end
  end

  @spec store_details(presence()) :: no_return()
  def store_details({_guild_id, _old, %{user: %{id: id}, status: status}}) do
    if status == :offline do
      case Data.get(Details, id) do
        nil -> %Details{member: id}
        entry -> entry
      end
      |> Details.changeset(%{online: Curie.local_datetime() |> Timex.to_unix()})
      |> Data.insert_or_update()
    end
  end

  @spec store_details(term()) :: nil
  def store_details(_unusable), do: nil

  @spec get_details(User.id()) :: {String.t(), String.t(), String.t()}
  def get_details(member_id) do
    case Data.get(Details, member_id) do
      nil ->
        {"Never seen online", "Never", "None"}

      %{online: online, spoke: spoke, channel: channel} ->
        {if(online, do: "Offline for " <> Curie.unix_to_amount(online)) || "Never seen online",
         if(spoke, do: Curie.unix_to_amount(spoke) <> " ago") || "Never", channel || "None"}
    end
  end

  @spec status_gather(presence()) :: no_return()
  def status_gather({guild_id, _old, %{game: %{name: game_name, type: 0}, user: %{id: user_id}}}) do
    if !Data.get(Status, game_name) do
      %Status{message: game_name, member: Curie.get_display_name(guild_id, user_id)}
      |> Data.insert()
    end
  end

  @spec status_gather(term()) :: nil
  def status_gather(_unusable), do: nil

  @spec change_member_standing(String.t(), User.id(), User.username(), Message.t()) :: Message.t()
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
  end

  @impl true
  def command({action, @owner = message, _args}) when action in ["whitelist", "remove"] do
    case Curie.get_member(message, 1) do
      {:ok, %{nick: nick, user: %{id: id, username: username}}} ->
        change_member_standing(action, id, nick || username, message)

      {:error, reason} ->
        Curie.embed(message, "Unable to #{action} member (#{reason}).", "red")
    end
  end

  @impl true
  def command(_call), do: nil

  @spec handler(map()) :: no_return()
  def handler(%{author: %{id: id}} = message) do
    if Curie.my_id() != id, do: store_details(message)
    super(message)
  end
end
