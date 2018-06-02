defmodule Curie.Announcements do
  alias Nostrum.Cache.{ChannelCache, UserCache}
  alias Nostrum.Api

  import Nostrum.Struct.Embed

  @notify 141_160_537_672_122_368

  def iso_to_unix(iso), do: iso |> Timex.parse!("{ISO:Extended}") |> Timex.to_unix()

  def join_log(guild_id, member) do
    with {:ok, invites} <- Api.get_guild_invites(guild_id),
         true <- !Enum.empty?(invites) do
      latest =
        invites
        |> Enum.filter(&(&1["uses"] > 0))
        |> Enum.max_by(&(&1["created_at"] |> iso_to_unix()), fn -> nil end)

      if !is_nil(latest) do
        content =
          "#{latest["inviter"]["username"]} invited #{member.user.username} " <>
            "to the server. (#{length(invites)})"

        Curie.embed(@notify, content, "dblue")
      end
    end
  end

  def delete_log(%{channel_id: channel_id}) do
    if channel_id != @notify do
      channel =
        ChannelCache.get!(channel_id)
        |> (&if(&1.name, do: "#" <> &1.name, else: "#DM")).()

      Curie.embed(@notify, "Message got deleted in #{channel}", "red")
    end
  end

  def leave_log(member) do
    content =
      if Timex.local() |> Timex.format!("%H%M", :strftime) == "0000",
        do: "#{member.user.username} was pruned for 30 days of inactivity #{Curie.time_now()}",
        else: "#{member.user.username} left #{Curie.time_now()}"

    Curie.embed(@notify, content, "dblue")
  end

  def has_cooldown?(member) do
    query = "SELECT time FROM streams WHERE member=$1"

    case Postgrex.query!(Postgrex, query, [member]).rows do
      [] ->
        false

      [[time]] ->
        (Timex.local() |> Timex.to_unix()) - time <= 21600
    end
  end

  def set_cooldown(member) do
    query = "SELECT time FROM streams WHERE member=$1"

    case Postgrex.query!(Postgrex, query, [member]).rows do
      [] ->
        query = "INSERT INTO streams (member, time) VALUES ($1, $2)"
        Postgrex.query!(Postgrex, query, [member, Timex.local() |> Timex.to_unix()])

      _entry ->
        query = "UPDATE streams SET time=$1 WHERE member=$2"
        Postgrex.query!(Postgrex, query, [Timex.local() |> Timex.to_unix(), member])
    end
  end

  def stream(presence) do
    if !is_nil(presence.game) and presence.game.type == 1 and !has_cooldown?(presence.user.id) do
      twitch_id = Application.get_env(:curie, :twitch)
      channel_name = presence.game.url |> String.split("/") |> List.last()
      url = "https://api.twitch.tv/kraken/channels/#{channel_name}/?client_id=#{twitch_id}"

      case Curie.get(url) do
        {200, response} ->
          details = response.body |> Poison.decode!()
          member = UserCache.get!(presence.user.id)
          content = "#{member.username} started streaming!"

          %Nostrum.Struct.Embed{}
          |> put_author(content, nil, Curie.avatar_url(member))
          |> put_description("[#{presence.game.name}](#{presence.game.url})")
          |> put_color(Curie.color("purple"))
          |> put_field("Playing:", details["game"], true)
          |> put_field("Channel:", "Twitch.tv/" <> details["display_name"], true)
          |> put_thumbnail(details["logo"])
          |> (&Curie.send(141_160_537_672_122_368, embed: &1)).()

          set_cooldown(member.id)

        {:failed, _reason} ->
          nil
      end
    end
  end
end
