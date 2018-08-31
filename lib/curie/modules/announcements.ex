defmodule Curie.Announcements do
  alias Nostrum.Struct.{Guild, Invite, Message, User}
  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Cache.UserCache
  alias Nostrum.Api

  alias Curie.Data.Streams
  alias Curie.Data

  import Nostrum.Struct.Snowflake, only: [is_snowflake: 1]
  import Nostrum.Struct.Embed

  @general Application.get_env(:curie, :channels).general
  @invisible Application.get_env(:curie, :channels).invisible

  @spec iso_to_unix(String.t()) :: non_neg_integer() | nil
  def iso_to_unix(iso) do
    case Timex.parse(iso, "{ISO:Extended}") do
      {:ok, datetime} -> Timex.to_unix(datetime)
      _unable_to_parse -> nil
    end
  end

  @spec join_log(Guild.id(), Member.t()) :: no_return()
  def join_log(guild_id, %{user: %{username: invitee}} = member) when is_snowflake(guild_id) do
    case Api.get_guild_invites(guild_id) do
      {:ok, invites} when invites != [] ->
        join_log(invites, member)

      _no_invites ->
        "#{invitee} joined with a one time invite. #{Curie.time_now()}"
        |> (&Curie.embed(@invisible, &1, "dblue")).()
    end
  end

  @spec join_log([Invite.t()], Member.t()) :: no_return()
  def join_log(invites, %{user: %{username: invitee}}) when is_list(invites) do
    with used when used != [] <- Enum.filter(invites, &(&1.uses > 0)),
         %Invite{} = %{inviter: %{username: inviter}} <-
           Enum.max_by(used, &iso_to_unix(&1.created_at), fn -> nil end) do
      "#{inviter} invited #{invitee} to the guild. (#{length(invites)}) #{Curie.time_now()}"
      |> (&Curie.embed(@invisible, &1, "dblue")).()
    end
  end

  @spec delete_log(%{channel_id: Message.channel_id()}) :: no_return()
  def delete_log(%{channel_id: channel_id}) do
    if channel_id != @invisible do
      channel_id
      |> Api.get_channel!()
      |> (&if(&1.name, do: "#" <> &1.name, else: "#DirectMessage")).()
      |> (&Curie.embed(@invisible, "Message got deleted in #{&1}", "red")).()
    end
  end

  @spec leave_log(Member.t()) :: no_return()
  def leave_log(%{user: %{username: member}}) do
    if Timex.local() |> Timex.format!("%H%M", :strftime) == "0000" do
      "#{member} was pruned for 30 days of inactivity #{Curie.time_now()}"
    else
      "#{member} left the guild. #{Curie.time_now()}"
    end
    |> (&Curie.embed(@invisible, &1, "dblue")).()
  end

  @spec has_cooldown?(User.id()) :: boolean()
  def has_cooldown?(member) do
    # Returns true if timestamp is less than 6h old
    case Data.get(Streams, member) do
      %{time: time} -> (Timex.local() |> Timex.to_unix()) - time <= 21600
      _no_cooldown -> false
    end
  end

  @spec set_cooldown(User.id()) :: no_return()
  def set_cooldown(member) do
    case Data.get(Streams, member) do
      nil -> %Streams{member: member}
      cooldown -> cooldown
    end
    |> Streams.changeset(%{time: Timex.local() |> Timex.to_unix()})
    |> Data.insert_or_update()
  end

  @spec stream(%{game: String.t(), user: %{id: User.id()}}) :: no_return()
  def stream(%{game: game, user: %{id: member}}) do
    if game != nil and game.type == 1 and not has_cooldown?(member) do
      twitch_id = Application.get_env(:curie, :twitch)
      channel_name = game.url |> String.split("/") |> List.last()
      url = "https://api.twitch.tv/kraken/channels/#{channel_name}/?client_id=#{twitch_id}"

      with {:ok, %{body: body}} <- Curie.get(url),
           {:ok, details} <- Poison.decode(body),
           {:ok, %{username: name} = user} <- UserCache.get(member),
           {:ok, _entry} <- set_cooldown(member) do
        %Nostrum.Struct.Embed{}
        |> put_author("#{name} started streaming!", nil, Curie.avatar_url(user))
        |> put_description("[#{game.name}](#{game.url})")
        |> put_color(Curie.color("purple"))
        |> put_field("Playing:", details["game"], true)
        |> put_field("Channel:", "Twitch.tv/" <> details["display_name"], true)
        |> put_thumbnail(details["logo"])
        |> (&Curie.send(@general, embed: &1)).()
      end
    end
  end
end
