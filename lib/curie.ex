defmodule Curie do
  import Nostrum.Api, only: [bangify: 1]
  import Nostrum.Struct.Embed

  alias Timex.AmbiguousDateTime

  alias Nostrum.Struct.{Channel, Guild, Message, User}
  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Cache.{GuildCache, UserCache, Me}
  alias Nostrum.Error.ApiError
  alias Nostrum.Api

  @type message_or_error :: {:ok, Message.t()} | {:error, ApiError.t()}
  @type destination :: Channel.id() | Message.t()
  @type options :: keyword() | map()

  @colors Application.get_env(:curie, :colors)

  @spec my_id() :: User.id() | nil
  def my_id do
    with %{id: curie} <- Me.get() do
      curie
    end
  end

  @spec color(String.t()) :: non_neg_integer() | nil
  def color(name) do
    @colors[name]
  end

  @spec local_datetime() :: DateTime.t()
  def local_datetime do
    case Timex.local() do
      %DateTime{} = time -> time
      %AmbiguousDateTime{} = time -> time.after
    end
  end

  @spec time_now() :: String.t()
  def time_now do
    local_datetime() |> Timex.format!("%H:%M:%S %d-%m-%Y", :strftime)
  end

  @spec avatar_url(User.t()) :: String.t()
  def avatar_url(user, format \\ "webp") do
    User.avatar_url(user, format) <> "?size=4096"
  end

  @spec check_typo(String.t(), String.t() | [String.t()]) :: String.t() | nil
  def check_typo(call, commands) do
    {match, similarity} =
      if(is_binary(commands), do: List.wrap(commands), else: commands)
      |> Enum.map(&{&1, call |> String.downcase() |> String.jaro_distance(&1)})
      |> Enum.max_by(fn {_call, similarity} -> similarity end)

    if similarity >= 0.75, do: match
  end

  @spec unix_to_amount(non_neg_integer()) :: String.t()
  def unix_to_amount(timestamp) do
    amount = (Curie.local_datetime() |> Timex.to_unix()) - timestamp
    {minutes, seconds} = {div(amount, 60), rem(amount, 60)}
    {hours, minutes} = {div(minutes, 60), rem(minutes, 60)}
    {days, hours} = {div(hours, 24), rem(hours, 24)}

    [{"d", days}, {"h", hours}, {"m", minutes}, {"s", seconds}]
    |> Enum.filter(fn {_key, value} -> value != 0 end)
    |> Enum.map_join(", ", fn {key, value} -> to_string(value) <> key end)
  end

  @spec embed!(destination(), String.t(), String.t() | non_neg_integer()) ::
          Message.t() | no_return()
  def embed!(channel, description, color) do
    embed(channel, description, color) |> bangify()
  end

  @spec embed(destination(), String.t(), String.t() | non_neg_integer()) :: message_or_error()
  def embed(channel, description, color) do
    channel = if is_map(channel), do: channel.channel_id, else: channel
    color = if is_integer(color), do: color, else: color(color)

    %Nostrum.Struct.Embed{}
    |> put_color(color)
    |> put_description(description)
    |> (&Curie.send(channel, embed: &1)).()
  end

  @spec send!(destination(), options()) :: Message.t() | no_return()
  def send!(channel, options) do
    Curie.send(channel, options) |> bangify()
  end

  @spec send(destination(), options(), non_neg_integer()) :: message_or_error()
  def send(channel, options, retries \\ 0) do
    channel = if is_map(channel), do: channel.channel_id, else: channel

    case Nostrum.Api.create_message(channel, options) do
      {:ok, _message} = result ->
        result

      {:error, %{status_code: code}} = error ->
        if code >= 500 and retries <= 10 do
          Process.sleep(2000)
          Curie.send(channel, options, retries + 1)
        else
          error
        end
    end
  end

  @spec edit!(Message.t(), options()) :: Message.t() | no_return()
  def edit!(message, options) do
    edit(message, options) |> bangify()
  end

  @spec edit!(Channel.id(), Message.id(), options()) :: Message.t() | no_return()
  def edit!(channel_id, message_id, options) do
    edit(channel_id, message_id, options) |> bangify()
  end

  @spec edit(%{channel_id: Channel.id(), id: Message.id()}, options()) :: message_or_error()
  def edit(%{channel_id: channel_id, id: message_id}, options) do
    edit(channel_id, message_id, options)
  end

  @spec edit(Channel.id(), Message.id(), options(), non_neg_integer()) :: message_or_error()
  def edit(channel_id, message_id, options, retries \\ 0) do
    case Nostrum.Api.edit_message(channel_id, message_id, options) do
      {:ok, _message} = result ->
        result

      {:error, %{status_code: code}} = error ->
        if code >= 500 and retries <= 10 do
          Process.sleep(250)
          edit(channel_id, message_id, options, retries + 1)
        else
          error
        end
    end
  end

  @spec get(String.t(), [{String.t(), String.t()}], non_neg_integer()) ::
          {:ok, HTTPoison.Respose.t()} | {:error, String.t()}
  def get(url, headers \\ [], retries \\ 0) when is_list(headers) do
    case HTTPoison.get(url, [{"Connection", "close"}] ++ headers, follow_redirect: true) do
      {:ok, response} = result ->
        case response.status_code do
          200 ->
            result

          code ->
            if code >= 500 and retries < 5 do
              Process.sleep(2000)
              get(url, headers, retries + 1)
            else
              {:error, Integer.to_string(code)}
            end
        end

      {:error, error} ->
        if retries < 5 do
          Process.sleep(2000)
          get(url, headers, retries + 1)
        else
          {:error, inspect(error.reason)}
        end
    end
  end

  @spec get_username(User.id()) :: String.t()
  def get_username(id) do
    case UserCache.get(id) do
      {:ok, %{username: name}} ->
        name

      {:error, _reason} ->
        case Api.get_user(id) do
          {:ok, %{username: name}} -> name
          {:error, _reason} -> "Unknown"
        end
    end
  end

  @spec get_member(Member.t() | nil) :: {:ok, Member.t()} | {:error, :member_not_found}
  def get_member(%Member{} = member), do: {:ok, member}
  def get_member(nil), do: {:error, :member_not_found}

  @spec get_member(Guild.id(), atom(), term()) :: {:ok, Member.t()} | {:error, atom()}
  def get_member(guild, key, value) do
    case GuildCache.select(guild, & &1.members) do
      {:ok, map} when key == :id ->
        get_member(map[value])

      {:ok, map} when key == :tag ->
        [name, disc] = Regex.run(~r/^(.+)#(\d{4})$/, value, capture: :all_but_first)
        find_by_tag = &(&1.user.username == name and &1.user.discriminator == disc)

        map
        |> Map.values()
        |> Enum.find(find_by_tag)
        |> get_member()

      {:ok, map} ->
        find_by_key = &(Map.get(&1.user, key) == value)

        map
        |> Map.values()
        |> Enum.find(find_by_key)
        |> get_member()

      {:error, _reason} = error ->
        error
    end
  end

  @spec get_member(
          %{guild_id: Guild.id(), content: String.t(), mentions: [User.t()]},
          non_neg_integer()
        ) :: {:ok, Member.t()} | {:error, atom()}
  def get_member(%{guild_id: guild, content: content, mentions: mentions}, position) do
    full_name =
      content
      |> String.split()
      |> (&Enum.slice(&1, position..length(&1))).()
      |> Enum.join(" ")

    if guild != nil and full_name != "" do
      cond do
        mentions != [] ->
          mentions
          |> List.first()
          |> (&get_member(guild, :id, &1.id)).()

        full_name =~ ~r/^\d+$/ ->
          full_name
          |> String.to_integer()
          |> (&get_member(guild, :id, &1)).()

        full_name =~ ~r/#\d{4}$/ ->
          get_member(guild, :tag, full_name)

        true ->
          get_member(guild, :username, full_name)
      end
    end
  end
end
