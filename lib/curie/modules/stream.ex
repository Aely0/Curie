defmodule Curie.Stream do
  import Nostrum.Struct.Embed

  alias Nostrum.Struct.{Embed, Guild, User}
  alias Nostrum.Cache.UserCache

  alias Curie.Data.Streams
  alias Curie.Data

  require Logger

  @cooldown Application.get_env(:curie, :stream_message_cooldown)
  @general Application.get_env(:curie, :channels).general

  @twitch_auth [{"Client-ID", Application.get_env(:curie, :twitch)}]

  @spec stored_stream_message(User.id()) :: {:ok, Streams.t()} | {:error, :no_previous_messages}
  def stored_stream_message(user_id) do
    case Data.get(Streams, user_id) do
      %Streams{} = message -> {:ok, message}
      nil -> {:error, :no_previous_messages}
    end
  end

  @spec has_cooldown?(Streams.t()) :: boolean
  def has_cooldown?(%Streams{time: time}),
    do: (Timex.now() |> Timex.to_unix()) - time <= @cooldown

  @spec set_cooldown(Curie.message_result(), User.id()) :: Curie.message_result()
  def set_cooldown({:ok, %{channel_id: channel_id, id: message_id}} = message, user_id) do
    (Data.get(Streams, user_id) || %Streams{member: user_id})
    |> Streams.changeset(%{
      time: Timex.now() |> Timex.to_unix(),
      channel_id: channel_id,
      message_id: message_id
    })
    |> Data.insert_or_update()

    message
  end

  def set_cooldown(error, _user_id), do: error

  @spec stream_data_gather(tuple, 0..10) :: {:ok, data :: tuple} | {:error, any}
  def stream_data_gather({guild_id, user_id, login, title, url, game} = params, retries \\ 0) do
    with channel_url = "https://api.twitch.tv/helix/streams?user_login=#{login}",
         {:ok, %{body: body}} <- Curie.get(channel_url, @twitch_auth),
         {:ok, %{"data" => [%{"user_name" => user} | _]}} <- Poison.decode(body),
         user_url = "https://api.twitch.tv/helix/users?login=#{login}",
         {:ok, %{body: body}} <- Curie.get(user_url, @twitch_auth),
         {:ok, %{"data" => [%{"profile_image_url" => image} | _]}} <-
           Poison.decode(body),
         {:ok, cached_user} <- UserCache.get(user_id) do
      name = Curie.get_display_name(guild_id, user_id)
      avatar = Curie.avatar_url(cached_user)

      {:ok, {name, avatar, title, url, game, user, image}}
    else
      _ when retries < 10 ->
        Process.sleep(20000)
        stream_data_gather(params, retries + 1)

      error ->
        error
    end
  end

  @spec stream_embed(tuple) :: Embed.t()
  def stream_embed({name, avatar, title, url, game, user, image}) do
    %Embed{}
    |> put_author("#{name} started streaming!", nil, avatar)
    |> put_description("[#{title}](#{url})")
    |> put_color(Curie.color("purple"))
    |> put_field("Playing:", game, true)
    |> put_field("Channel:", "Twitch.tv/" <> user, true)
    |> put_thumbnail(image)
  end

  @spec stream_message(User.id(), tuple) :: Curie.message_result()
  def stream_message(user_id, data) do
    with {:ok, %Streams{channel_id: channel_id, message_id: message_id} = stream} <-
           stored_stream_message(user_id),
         true <- has_cooldown?(stream) do
      Curie.edit(channel_id, message_id, embed: stream_embed(data))
    else
      _no_previous_stream_messages_or_cooldown ->
        @general
        |> Curie.send(embed: stream_embed(data))
        |> set_cooldown(user_id)
    end
  end

  @spec stream({Guild.id(), map, map}) :: Curie.message_result() | :pass
  def stream(
        {guild_id, _old,
         %{
           game: %{
             type: 1,
             details: title,
             state: game,
             url: "https://www.twitch.tv/" <> login = url
           },
           user: %{id: user_id}
         }}
      ) do
    {guild_id, user_id, login, title, url, game}
    |> stream_data_gather()
    |> case do
      {:ok, data} ->
        stream_message(user_id, data)

      {:error, error} ->
        Logger.warn("Stream #{inspect(error)}")
        :pass
    end
  end

  def stream(_presence), do: :pass
end
