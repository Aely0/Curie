defmodule Curie.Announcements do
  import Nostrum.Snowflake, only: [is_snowflake: 1]
  import Nostrum.Struct.Embed

  alias Nostrum.Struct.{Guild, Invite, User}
  alias Nostrum.Struct.Event.MessageDelete
  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Cache.UserCache
  alias Nostrum.Api

  alias Curie.MessageCache
  alias Curie.Data.Streams
  alias Curie.Data

  @general Application.get_env(:curie, :channels).general
  @invisible Application.get_env(:curie, :channels).invisible
  @logs Application.get_env(:curie, :channels).logs

  @spec iso_to_unix(String.t()) :: non_neg_integer | nil
  def iso_to_unix(iso) do
    case Timex.parse(iso, "{ISO:Extended}") do
      {:ok, datetime} -> Timex.to_unix(datetime)
      _unable_to_parse -> nil
    end
  end

  @spec join_log(Guild.id() | [Invite.t()], Member.t()) :: Curie.message_result() | []
  def join_log(guild_id, %{user: %{username: invitee}} = member) when is_snowflake(guild_id) do
    case Api.get_guild_invites(guild_id) do
      {:ok, invites} when invites != [] ->
        join_log(invites, member)

      _no_invites ->
        "#{invitee} joined with a one time invite. #{Curie.time_now()}"
        |> (&Curie.embed(@logs, &1, "dblue")).()
    end
  end

  def join_log(invites, %{user: %{username: invitee}}) when is_list(invites) do
    with used when used != [] <- Enum.filter(invites, &(&1.uses > 0)),
         %Invite{} = %{inviter: %{username: inviter}} <-
           Enum.max_by(used, &iso_to_unix(&1.created_at), fn -> nil end) do
      "#{inviter} invited #{invitee} to the guild. (#{length(invites)}) #{Curie.time_now()}"
      |> (&Curie.embed(@logs, &1, "dblue")).()
    end
  end

  @spec delete_log(MessageDelete.t()) :: Curie.message_result() | :ignore | {:error, any}
  def delete_log(%{guild_id: guild_id, channel_id: channel_id} = deleted_message) do
    with true <- channel_id not in [@invisible, @logs] and guild_id != nil,
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
      |> (&Curie.embed(@logs, &1, "red")).()
    else
      false ->
        :ignore

      {:error, :not_found} ->
        {:ok, %{name: channel_name}} = Api.get_channel(channel_id)

        "Message deleted in ##{channel_name}"
        |> (&Curie.embed(@logs, &1, "red")).()

      {:error, reason} ->
        "Delete log failed (#{inspect(reason)})"
        |> (&Curie.embed(@logs, &1, "red")).()
    end
  end

  @spec leave_log(Member.t()) :: Curie.message_result()
  def leave_log(%{user: %{username: name}}) do
    case :calendar.local_time() do
      {_, {0, 0, _}} ->
        "#{name} was pruned for 30 days of inactivity #{Curie.time_now("%d-%m-%Y")}"

      _time ->
        "#{name} left the guild. #{Curie.time_now()}"
    end
    |> (&Curie.embed(@logs, &1, "dblue")).()
  end

  @spec has_cooldown?(User.id()) :: boolean
  def has_cooldown?(member_id) do
    # Cooldown of 6 hours
    case Data.get(Streams, member_id) do
      %{time: time} -> (Timex.now() |> Timex.to_unix()) - time <= 21600
      _no_cooldown -> false
    end
  end

  @spec set_cooldown(User.id()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def set_cooldown(member_id) do
    (Data.get(Streams, member_id) || %Streams{member: member_id})
    |> Streams.changeset(%{time: Timex.now() |> Timex.to_unix()})
    |> Data.insert_or_update()
  end

  @spec stream({Guild.id(), map, %{game: String.t(), user: %{id: User.id()}}}, 0..5) ::
          Curie.message_result() | :pass
  def stream({guild_id, _old, %{game: game, user: %{id: member_id}}} = presence, retries \\ 0) do
    if game != nil and game.type == 1 and not has_cooldown?(member_id) do
      auth = [{"Client-ID", Application.get_env(:curie, :twitch)}]
      channel = game.url |> String.split("/") |> List.last()

      with channel_url = "https://api.twitch.tv/helix/streams?user_login=#{channel}",
           {:ok, %{body: body}} <- Curie.get(channel_url, auth),
           {:ok, %{"data" => [%{"user_name" => channel_name, "title" => title} = channel | _]}} <-
             Poison.decode(body),
           game_url = "https://api.twitch.tv/helix/games?id=#{channel["game_id"]}",
           {:ok, %{body: body}} <- Curie.get(game_url, auth),
           {:ok, %{"data" => [%{"name" => stream_game} | _]}} <- Poison.decode(body),
           user_url = "https://api.twitch.tv/helix/users?id=#{channel["user_id"]}",
           {:ok, %{body: body}} <- Curie.get(user_url, auth),
           {:ok, %{"data" => [%{"profile_image_url" => profile_image} | _]}} <-
             Poison.decode(body),
           {:ok, %{id: user_id} = user} <- UserCache.get(member_id),
           name = Curie.get_display_name(guild_id, user_id),
           {:ok, _} <- set_cooldown(member_id) do
        %Nostrum.Struct.Embed{}
        |> put_author("#{name} started streaming!", nil, Curie.avatar_url(user))
        |> put_description("[#{title}](#{game.url})")
        |> put_color(Curie.color("purple"))
        |> put_field("Playing:", stream_game, true)
        |> put_field("Channel:", "Twitch.tv/" <> channel_name, true)
        |> put_thumbnail(profile_image)
        |> (&Curie.send(@general, embed: &1)).()
      else
        _ when retries <= 5 ->
          Task.start(fn ->
            Process.sleep(20000)
            stream(presence, retries + 1)
          end)

        _ ->
          :pass
      end
    else
      :pass
    end
  end
end
