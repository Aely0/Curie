defmodule Curie.Storage do
  use Curie.Commands

  alias Nostrum.Cache.{ChannelCache, UserCache, Me}
  alias Nostrum.Struct.{Channel, Message, User}

  alias Curie.Data.{Balance, Details, Status}
  alias Curie.Data

  @spec remove(User.id()) :: no_return()
  def remove(member) do
    for table <- [Balance, Details] do
      table
      |> Data.get(member)
      |> (&if(&1, do: Data.delete(&1))).()
    end
  end

  @spec store_details(%{author: %{id: User.id()}, channel_id: Channel.id(), type: Message.type()}) ::
          no_return()
  def store_details(%{author: %{id: id}, channel_id: channel_id, type: type}) do
    with {:ok, %Channel{name: name}} when type == 0 <- ChannelCache.get(channel_id) do
      case Data.get(Details, id) do
        nil -> %Details{member: id}
        entry -> entry
      end
      |> Details.changeset(%{
        spoke: Timex.local() |> Timex.to_unix(),
        channel: if(name, do: "##{name}", else: "#DirectMessage")
      })
      |> Data.insert_or_update()
    end
  end

  @spec store_details(%{user: %{id: User.id()}, status: atom()}) :: no_return()
  def store_details(%{user: %{id: id}, status: status}) do
    if status == :offline do
      case Data.get(Details, id) do
        nil -> %Details{member: id}
        entry -> entry
      end
      |> Details.changeset(%{online: Timex.local() |> Timex.to_unix()})
      |> Data.insert_or_update()
    end
  end

  @spec store_details(term()) :: nil
  def store_details(_unusable), do: nil

  @spec fetch_details(User.id()) ::
          %{online: String.t(), spoke: String.t(), channel: String.t()} | Details.t()
  def fetch_details(member) do
    case Data.get(Details, member) do
      nil ->
        %{online: "Never seen online", spoke: "Never", channel: "None"}

      details ->
        details
        |> (&if(&1.online == nil, do: %{&1 | online: "Never seen online"}, else: &1)).()
        |> (&if(&1.spoke == nil, do: %{&1 | spoke: "Never"}, else: &1)).()
        |> (&if(&1.channel == nil, do: %{&1 | channel: "None"}, else: &1)).()
    end
  end

  @spec status_gather(%{game: String.t(), user: User.t()}) :: no_return()
  def status_gather(%{game: game, user: %{id: user}} = _presence) do
    if game != nil and game.type == 0 and Data.get(Status, game.name) == nil do
      user
      |> UserCache.get!()
      |> Map.get(:username)
      |> (&%Status{message: game.name, member: &1}).()
      |> Data.insert()
    end
  end

  @spec change_member_standing(String.t(), User.id(), User.username(), Message.t()) :: Message.t()
  def change_member_standing("whitelist", id, name, %{guild_id: guild} = message) do
    if Balance |> Data.get(id) |> is_nil() do
      %Balance{member: id, value: 0, guild: guild}
      |> Data.insert()

      "#{name} added, wooo! :tada:"
      |> (&Curie.embed(message, &1, "green")).()
    else
      "Member already whitelisted."
      |> (&Curie.embed(message, &1, "red")).()
    end
  end

  def change_member_standing("remove", id, name, message) do
    case Data.get(Balance, id) do
      nil ->
        "Already does not exist. Job's done... I guess?"
        |> (&Curie.embed(message, &1, "red")).()

      member ->
        Data.delete(member)

        "#{name} removed, never liked that one anyway."
        |> (&Curie.embed(message, &1, "green")).()
    end
  end

  @impl true
  def command({action, @owner = message, _args}) when action in ["whitelist", "remove"] do
    case Curie.get_member(message, 1) do
      nil ->
        Curie.embed(message, "Member not found.", "red")

      %{user: %{id: id, username: username}} ->
        change_member_standing(action, id, username, message)
    end
  end

  @impl true
  def command(_call), do: nil

  @spec handler(map()) :: no_return()
  def handler(%{author: %{id: id}} = message) do
    if Me.get().id != id do
      store_details(message)
    end

    super(message)
  end
end
