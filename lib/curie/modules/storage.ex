defmodule Curie.Storage do
  alias Nostrum.Cache.{ChannelCache, UserCache, Me}

  alias Curie.Data.{Balance, Details, Status}
  alias Curie.Data

  @owner Curie.owner()

  def remove(member) do
    for table <- [Balance, Details],
        do: Data.get(table, member) |> (&if(&1, do: Data.delete(&1))).()
  end

  def store_details(%{author: %{id: id}, channel_id: channel_id, type: type}) do
    channel = ChannelCache.get!(channel_id)

    if type == 0 do
      now = Timex.local() |> Timex.to_unix()
      channel_name = if channel.name, do: "#" <> channel.name, else: "#DirectMessage"

      case Data.get(Details, id) do
        nil ->
          %Details{member: id}

        entry ->
          entry
      end
      |> Details.changeset(%{spoke: now, channel: channel_name})
      |> Data.insert_or_update()
    end
  end

  def store_details(%{user: %{id: id}, status: status}) do
    if status == :offline do
      now = Timex.local() |> Timex.to_unix()

      case Data.get(Details, id) do
        nil ->
          %Details{member: id}

        entry ->
          entry
      end
      |> Details.changeset(%{online: now})
      |> Data.insert_or_update()
    end
  end

  def store_details(_unusable), do: nil

  def fetch_details(member) do
    case Data.get(Details, member) do
      nil ->
        %{online: "Never seen online", spoke: "Never", channel: "None"}

      details ->
        details
        |> (&if(is_nil(&1.online), do: %{&1 | online: "Never seen online"}, else: &1)).()
        |> (&if(is_nil(&1.spoke), do: %{&1 | spoke: "Never"}, else: &1)).()
        |> (&if(is_nil(&1.channel), do: %{&1 | channel: "None"}, else: &1)).()
    end
  end

  def status_gather(presence) do
    if !is_nil(presence.game) and presence.game.type == 0 do
      if Data.get(Status, presence.game.name) |> is_nil() do
        member = UserCache.get!(presence.user.id).username

        %Status{message: presence.game.name, member: member}
        |> Data.insert()
      end
    end
  end

  def command({action, @owner = message, _words}) when action in ["whitelist", "remove"] do
    case Curie.get_member(message, 1) do
      nil ->
        Curie.embed(message, "Member not found.", "red")

      %{user: user} ->
        case action do
          "whitelist" ->
            if Data.get(Balance, user.id) |> is_nil() do
              %Balance{member: user.id, value: 0}
              |> Data.insert()

              "#{user.username} added, wooo! :tada:"
              |> (&Curie.embed(message, &1, "green")).()
            else
              "Member already whitelisted."
              |> (&Curie.embed(message, &1, "red")).()
            end

          "remove" ->
            case Data.get(Balance, user.id) do
              nil ->
                "Already does not exist. Job's done... I guess?"
                |> (&Curie.embed(message, &1, "red")).()

              member ->
                Data.delete(member)

                "#{user.username} removed, never liked that one anyway."
                |> (&Curie.embed(message, &1, "green")).()
            end
        end
    end
  end

  def command(_unknown_command), do: nil

  def handler(message) do
    if Me.get().id != message.author.id, do: store_details(message)
    if Curie.command?(message), do: message |> Curie.parse() |> command()
  end
end
