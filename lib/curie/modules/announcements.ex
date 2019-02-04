defmodule Curie.Announcements do
  import Nostrum.Struct.Snowflake, only: [is_snowflake: 1]
  import Nostrum.Struct.Embed

  alias Nostrum.Struct.{Guild, Invite, User}
  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Cache.UserCache
  alias Nostrum.Api

  alias Curie.MessageCache
  alias Curie.Data.Streams
  alias Curie.Data

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

  @spec delete_log(map_with_message_id_channel_id_maybe_guild_id :: map()) :: no_return()
  def delete_log(%{guild_id: guild_id, channel_id: channel_id} = deleted_message) do
    with true <- channel_id != @invisible and guild_id != nil,
         {:ok, [message | _] = messages} <- MessageCache.get(deleted_message),
         {:ok, %{name: channel_name}} <- Api.get_channel(channel_id) do
      %{username: name, discriminator: disc} =
        Map.get(message, :author) || Map.get(message, :user)

      details =
        for %{content: content, attachments: files, embeds: embeds} <- messages do
          content = if content == "", do: "No Content", else: content
          files = if files != [], do: " " <> (files |> Enum.map(& &1.filename) |> inspect())
          embeds = if embeds != [], do: " " <> inspect(embeds)
          "#{content}#{files}#{embeds}"
        end
        |> Enum.join(", edit: ")

      "##{channel_name} #{name}##{disc}: #{details}"
      |> (&Curie.embed(@invisible, &1, "red")).()
    else
      false ->
        :ignore

      {:error, :not_found} ->
        {:ok, %{name: channel_name}} = Api.get_channel(channel_id)

        "Message deleted in ##{channel_name}"
        |> (&Curie.embed(@invisible, &1, "red")).()

      {:error, reason} ->
        "Delete log failed (#{inspect(reason)})"
        |> (&Curie.embed(@invisible, &1, "red")).()
    end
  end

  @spec leave_log(Member.t()) :: no_return()
  def leave_log(%{user: %{username: name}}) do
    case Curie.local_datetime() do
      %{hour: 0, minute: 0} ->
        "#{name} was pruned for 30 days of inactivity #{Curie.time_now()}"

      _time ->
        "#{name} left the guild. #{Curie.time_now()}"
    end
    |> (&Curie.embed(@invisible, &1, "dblue")).()
  end

  @spec has_cooldown?(User.id()) :: boolean()
  def has_cooldown?(member_id) do
    # Returns true if timestamp is less than 6h old
    case Data.get(Streams, member_id) do
      %{time: time} -> (Curie.local_datetime() |> Timex.to_unix()) - time <= 21600
      _no_cooldown -> false
    end
  end

  @spec set_cooldown(User.id()) :: no_return()
  def set_cooldown(member_id) do
    (Data.get(Streams, member_id) || %Streams{member: member_id})
    |> Streams.changeset(%{time: Curie.local_datetime() |> Timex.to_unix()})
    |> Data.insert_or_update()
  end

  @spec stream({Guild.id(), map(), %{game: String.t(), user: %{id: User.id()}}}) :: no_return()
  def stream({guild_id, _old, %{game: game, user: %{id: member_id}}}) do
    if game != nil and game.type == 1 and not has_cooldown?(member_id) do
      twitch_id = Application.get_env(:curie, :twitch)
      channel_name = game.url |> String.split("/") |> List.last()
      url = "https://api.twitch.tv/kraken/channels/#{channel_name}/?client_id=#{twitch_id}"

      with {:ok, %{body: body}} <- Curie.get(url),
           {:ok, details} <- Poison.decode(body),
           {:ok, %{id: user_id} = user} <- UserCache.get(member_id),
           name = Curie.get_display_name(guild_id, user_id),
           {:ok, _entry} <- set_cooldown(member_id) do
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
