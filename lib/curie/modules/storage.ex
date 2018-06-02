defmodule Curie.Storage do
  alias Nostrum.Cache.{ChannelCache, UserCache, Me}

  @owner Curie.owner()

  def remove(member) do
    Postgrex.query!(Postgrex, "DELETE FROM balance WHERE member=$1", [member])
    Postgrex.query!(Postgrex, "DELETE FROM details WHERE member=$1", [member])
  end

  def check_entry(member) do
    query = "SELECT member FROM details WHERE member=$1"

    if Postgrex.query!(Postgrex, query, [member]).rows == [] do
      query = "INSERT INTO details (member) VALUES ($1)"
      Postgrex.query!(Postgrex, query, [member])
    end
  end

  def store_details(%{author: author, channel_id: channel_id, type: type}) do
    check_entry(author.id)

    channel = ChannelCache.get!(channel_id)

    if type == 0 do
      now = Timex.local() |> Timex.to_unix()
      channel_name = if channel.name, do: "#" <> channel.name, else: "#DirectMessage"
      query = "UPDATE details SET spoke=$1, channel=$2 WHERE member=$3"
      Postgrex.query!(Postgrex, query, [now, channel_name, author.id])
    end
  end

  def store_details(%{user: user, status: status}) do
    check_entry(user.id)

    if status == :offline do
      now = Timex.local() |> Timex.to_unix()
      query = "UPDATE details SET online=$1 WHERE member=$2"
      Postgrex.query!(Postgrex, query, [now, user.id])
    end
  end

  def store_details(_unusable), do: nil

  def fetch_details(member) do
    query = "SELECT online, spoke, channel FROM details WHERE member=$1"

    case Postgrex.query!(Postgrex, query, [member]).rows do
      [] ->
        %{online: "Never seen online", spoke: "Never", channel: "None"}

      [[online, spoke, channel]] ->
        %{online: online, spoke: spoke, channel: channel}
        |> (&if(is_nil(&1.online), do: %{&1 | online: "Never seen online"}, else: &1)).()
        |> (&if(is_nil(&1.spoke), do: %{&1 | spoke: "Never"}, else: &1)).()
        |> (&if(is_nil(&1.channel), do: %{&1 | channel: "None"}, else: &1)).()
    end
  end

  def status_gather(presence) do
    if !is_nil(presence.game) and presence.game.type == 0 do
      query = "SELECT message FROM status WHERE message=$1"

      case Postgrex.query!(Postgrex, query, [presence.game.name]).rows do
        [] ->
          member = UserCache.get!(presence.user.id).username
          query = "INSERT INTO status (message, member) VALUES ($1, $2)"
          Postgrex.query!(Postgrex, query, [presence.game.name, member])

        _exists ->
          nil
      end
    end
  end

  def command({action, @owner = message, _words}) do
    if action in ["whitelist", "remove"] do
      case Curie.get_member(message, 1) do
        nil ->
          Curie.embed(message, "Member not found.", "red")

        member ->
          case action do
            "whitelist" ->
              query = "SELECT member FROM balance WHERE member=$1"

              case Postgrex.query!(Postgrex, query, [member.user.id]).rows do
                [] ->
                  query = "INSERT INTO balance (member, value) VALUES ($1, 0)"
                  Postgrex.query!(Postgrex, query, [member.user.id])

                  "#{member.user.username} added, wooo! :tada:"
                  |> (&Curie.embed(message, &1, "green")).()

                _exists ->
                  "Member already whitelisted."
                  |> (&Curie.embed(message, &1, "red")).()
              end

            "remove" ->
              query = "SELECT member FROM balance WHERE member=$1"

              case Postgrex.query!(Postgrex, query, [member.user.id]).rows do
                [] ->
                  "Already does not exist. Job's done ...I guess?"
                  |> (&Curie.embed(message, &1, "red")).()

                _exists ->
                  query = "DELETE FROM balance WHERE member=$1"
                  Postgrex.query!(Postgrex, query, [member.user.id])

                  "#{member.user.username} removed, never liked that one anyway."
                  |> (&Curie.embed(message, &1, "green")).()
              end
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
