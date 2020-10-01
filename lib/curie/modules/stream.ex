defmodule Curie.Stream do
  @moduledoc """
  Member Twitch stream notification.
  """

  use GenServer

  import Nostrum.Struct.Embed

  alias Nostrum.Struct.{Embed, Guild, Message, User}
  alias Nostrum.Cache.UserCache

  alias Curie.Data.Streams
  alias Curie.Data

  require Logger

  @type twitch_auth_token_result :: {:ok, String.t()} | {:error, String.t()}
  @type header_result :: {:ok, [{String.t(), String.t()}]} | {:error, String.t()}

  @self __MODULE__

  @cooldown Application.get_env(:curie, :stream_message_cooldown)
  @general Application.get_env(:curie, :channels).general

  @twitch_client_id Application.get_env(:curie, :twitch_client_id)
  @twitch_client_secret Application.get_env(:curie, :twitch_client_secret)

  # 5 minutes (in seconds)
  @token_refresh_threshold 300

  @spec start_link(any) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl GenServer
  @spec init(any) :: {:ok, {:error, :not_ready}, {:continue, :fetch_token}}
  def init(_args) do
    {:ok, {:error, :not_ready}, {:continue, :fetch_token}}
  end

  @impl GenServer
  @spec handle_continue(:fetch_token, any) :: {:noreply, any}
  def handle_continue(:fetch_token, _state) do
    {:noreply, fetch_token()}
  end

  @impl GenServer
  def handle_call(:get_token, _from, token) do
    {:reply, token, token}
  end

  @impl GenServer
  def handle_call(:refresh_token, _from, _token) do
    token = fetch_token()
    {:reply, token, token}
  end

  @spec get_token :: twitch_auth_token_result
  def get_token, do: GenServer.call(@self, :get_token)

  @spec refresh_token :: twitch_auth_token_result
  def refresh_token, do: GenServer.call(@self, :refresh_token)

  @spec create_headers :: header_result
  def create_headers do
    case validate_token() do
      {:ok, token} ->
        {:ok, [{"Client-ID", @twitch_client_id}, {"Authorization", "Bearer " <> token}]}

      {:error, error} ->
        {:error, "Unable to create headers: " <> error}
    end
  end

  @spec validate_token :: twitch_auth_token_result
  def validate_token do
    with {:ok, token} = token_ok <- get_token(),
         headers = [{"Authorization", "OAuth " <> token}],
         {:ok, %{body: body}} <- Curie.get("https://id.twitch.tv/oauth2/validate", headers),
         {:expiration, {:ok, %{"expires_in" => time}}} when time >= @token_refresh_threshold <-
           {:expiration, Jason.decode(body)} do
      token_ok
    else
      {:expiration, {:ok, _expiring_soon}} -> refresh_token()
      error -> error
    end
  end

  @spec fetch_token(0..10) :: twitch_auth_token_result
  def fetch_token(retries \\ 0) do
    ("https://id.twitch.tv/oauth2/token?grant_type=client_credentials" <>
       "&client_id=#{@twitch_client_id}" <>
       "&client_secret=#{@twitch_client_secret}")
    |> HTTPoison.post("")
    |> case do
      {:ok, %{body: body, status_code: 200}} ->
        %{"access_token" => token} = Jason.decode!(body)
        {:ok, token}

      {:ok, %{body: body, status_code: code}} when code >= 500 and retries < 10 ->
        Logger.warn("Twitch API #{code}: #{body}")
        Process.sleep(1000)
        fetch_token(retries + 1)

      {:ok, %{body: body, status_code: code}} ->
        response = body |> Jason.decode!() |> inspect()
        Logger.warn("Twitch API #{code}: #{response}")
        {:error, response}

      {:error, error} when retries < 10 ->
        Logger.warn("Stream fetch_token/1 (retry): #{inspect(error)}")
        Process.sleep(1000)
        fetch_token(retries + 1)

      {:error, error} ->
        Logger.warn("Stream fetch_token/1 (failure): #{inspect(error)}")
        {:error, inspect(error)}
    end
  end

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

  @spec set_cooldown(Message.t(), User.id()) :: Message.t()
  def set_cooldown(%{channel_id: channel_id, id: message_id} = message, user_id) do
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
    with {:ok, headers} <- create_headers(),
         channel_url = "https://api.twitch.tv/helix/streams?user_login=#{login}",
         {:ok, %{body: body}} <- Curie.get(channel_url, headers),
         {:ok, %{"data" => [%{"user_name" => user} | _]}} <- Jason.decode(body),
         user_url = "https://api.twitch.tv/helix/users?login=#{login}",
         {:ok, %{body: body}} <- Curie.get(user_url, headers),
         {:ok, %{"data" => [%{"profile_image_url" => image} | _]}} <-
           Jason.decode(body),
         {:ok, cached_user} <- UserCache.get(user_id) do
      name = Curie.get_display_name(guild_id, user_id)
      avatar = Curie.avatar_url(cached_user)

      {:ok, {name, avatar, title, url, game, user, image}}
    else
      _ when retries < 10 ->
        Process.sleep(20_000)
        stream_data_gather(params, retries + 1)

      error ->
        {:error, inspect(error)}
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

  @spec stream_message(User.id(), tuple) :: Message.t() | no_return
  def stream_message(user_id, data) do
    with {:ok, %Streams{channel_id: channel_id, message_id: message_id} = stream} <-
           stored_stream_message(user_id),
         true <- has_cooldown?(stream) do
      Curie.edit!(channel_id, message_id, embed: stream_embed(data))
    else
      _no_previous_stream_messages_or_cooldown ->
        @general
        |> Curie.send!(embed: stream_embed(data))
        |> set_cooldown(user_id)
    end
  end

  @spec stream({Guild.id(), map, map}) :: Message.t() | no_return | :pass
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
        Logger.warn("Stream data gather: #{error}")
        :pass
    end
  end

  def stream(_presence), do: :pass
end
