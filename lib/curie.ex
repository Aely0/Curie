defmodule Curie do
  @moduledoc """
  Generic top level utility functions.
  """

  import Nostrum.Api, only: [bangify: 1]
  import Nostrum.Struct.Embed

  alias Nostrum.Api
  alias Nostrum.Cache.{GuildCache, Me, UserCache}
  alias Nostrum.Error.ApiError
  alias Nostrum.Snowflake
  alias Nostrum.Struct.{Channel, Guild, Message, User}
  alias Nostrum.Struct.Guild.Member

  @type message_result :: {:ok, Message.t()} | Api.error()
  @type destination :: Channel.id() | Message.t()
  @type options :: keyword | map | String.t()

  @colors Application.compile_env(:curie, :colors)

  @spec my_id :: {:ok, User.id()} | {:error, ApiError.t() | HTTPoison.Error.t()}
  def my_id do
    case Me.get() do
      %User{id: id} ->
        {:ok, id}

      _not_found ->
        case Api.get_current_user() do
          {:ok, %User{id: id}} -> {:ok, id}
          {:error, _reason} = error -> error
        end
    end
  end

  @spec color(String.t()) :: non_neg_integer | nil
  def color(name) do
    @colors[name]
  end

  @spec time_now(strftime_format :: String.t()) :: String.t()
  def time_now(format \\ "%H:%M:%S %d-%m-%Y") do
    :calendar.local_time() |> Timex.format!(format, :strftime)
  end

  @spec avatar_url(User.t(), String.t()) :: String.t()
  def avatar_url(user, format \\ "webp") do
    User.avatar_url(user, format) <> "?size=4096"
  end

  @spec check_typo(String.t(), String.t() | [String.t()]) :: String.t() | nil
  def check_typo(call, commands) do
    {match, similarity} =
      if(is_binary(commands), do: List.wrap(commands), else: commands)
      |> Enum.map(&{&1, call |> String.downcase() |> String.jaro_distance(&1)})
      |> Enum.max_by(fn {_call, similarity} -> similarity end)

    if similarity > 0.75, do: match
  end

  @spec unix_to_amount(non_neg_integer) :: String.t()
  def unix_to_amount(timestamp) when is_integer(timestamp) and timestamp >= 0 do
    amount = Timex.to_unix(Timex.now()) - timestamp
    {minutes, seconds} = {div(amount, 60), rem(amount, 60)}
    {hours, minutes} = {div(minutes, 60), rem(minutes, 60)}
    {days, hours} = {div(hours, 24), rem(hours, 24)}

    [{"d", days}, {"h", hours}, {"m", minutes}, {"s", seconds}]
    |> Enum.filter(fn {_key, value} -> value != 0 end)
    |> Enum.map_join(", ", fn {key, value} -> to_string(value) <> key end)
  end

  @spec embed!(destination, String.t(), String.t() | non_neg_integer) ::
          Message.t() | no_return
  def embed!(channel_or_message, description, color) do
    embed(channel_or_message, description, color) |> bangify()
  end

  @spec embed(destination, String.t(), String.t() | non_neg_integer) :: message_result
  def embed(channel_or_message, description, color) do
    color = if is_integer(color), do: color, else: color(color)

    %Nostrum.Struct.Embed{}
    |> put_color(color)
    |> put_description(description)
    |> (&Curie.send(channel_or_message, embed: &1)).()
  end

  @spec send!(destination, options) :: Message.t() | no_return
  def send!(channel_or_message, options) do
    Curie.send(channel_or_message, options) |> bangify()
  end

  @spec send(destination, options, non_neg_integer) :: message_result
  def send(channel_or_message, options, retries \\ 0) do
    case Nostrum.Api.create_message(channel_or_message, options) do
      {:ok, _message} = result ->
        result

      {:error, %{status_code: code}} when code >= 500 and retries <= 10 ->
        Process.sleep(500)
        Curie.send(channel_or_message, options, retries + 1)

      {:error, %{status_code: 403}} = error ->
        error

      {:error, _error} when retries <= 5 ->
        Process.sleep(500)
        Curie.send(channel_or_message, options, retries + 1)

      error ->
        error
    end
  end

  @spec edit!(%{channel_id: Channel.id(), id: Message.id()}, options) :: Message.t() | no_return
  def edit!(message, options) do
    edit(message, options) |> bangify()
  end

  @spec edit!(Channel.id(), Message.id(), options) :: Message.t() | no_return
  def edit!(channel_id, message_id, options) do
    edit(channel_id, message_id, options) |> bangify()
  end

  @spec edit(%{channel_id: Channel.id(), id: Message.id()}, options) :: message_result
  def edit(%{channel_id: channel_id, id: message_id}, options) do
    edit(channel_id, message_id, options)
  end

  @spec edit(Channel.id(), Message.id(), options, non_neg_integer) :: message_result
  def edit(channel_id, message_id, options, retries \\ 0) do
    case Nostrum.Api.edit_message(channel_id, message_id, options) do
      {:ok, _message} = result ->
        result

      {:error, %{status_code: code}} when code >= 500 and retries <= 5 ->
        Process.sleep(500)
        edit(channel_id, message_id, options, retries + 1)

      {:error, %{status_code: 403}} = error ->
        error

      {:error, _error} when retries <= 5 ->
        Process.sleep(500)
        edit(channel_id, message_id, options, retries + 1)

      error ->
        error
    end
  end

  @spec get(String.t(), [{String.t(), String.t()}], non_neg_integer) ::
          {:ok, HTTPoison.Respose.t()} | {:error, String.t()}
  def get(url, headers \\ [], retries \\ 0) when is_list(headers) do
    case HTTPoison.get(url, [{"Connection", "close"}] ++ headers, follow_redirect: true) do
      {:ok, %{status_code: 200}} = response ->
        response

      {:ok, %{status_code: code}} when code >= 500 and retries < 5 ->
        Process.sleep(500)
        get(url, headers, retries + 1)

      {:ok, %{status_code: code}} ->
        {:error, Integer.to_string(code)}

      {:error, _error} when retries < 5 ->
        Process.sleep(500)
        get(url, headers, retries + 1)

      {:error, %{reason: reason}} ->
        {:error, inspect(reason)}
    end
  end

  @spec get_display_name(Message.t()) :: String.t()
  def get_display_name(%{member: member, guild_id: guild_id, author: user}) do
    cond do
      member -> member.nick || user.username
      guild_id -> get_display_name(guild_id, user.id)
      user -> get_username(user.id)
    end
  end

  @spec get_display_name(Guild.id(), User.id()) :: String.t()
  def get_display_name(guild_id, user_id) do
    case get_member({guild_id, :id, user_id}) do
      {:ok, %{nick: nick, user: %{username: name}}} ->
        nick || name

      {:error, _reason} ->
        case Api.get_guild_member(guild_id, user_id) do
          {:ok, %{nick: nick, user: %{username: name}}} ->
            nick || name

          {:error, _reason} ->
            get_username(user_id)
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

  @spec find_member(%{User.id() => Member.t()}, (Member.t() -> boolean)) ::
          {:ok, Member.t()} | {:error, :member_not_found}
  def find_member(members, check) do
    members
    |> Map.values()
    |> Enum.find(check)
    |> case do
      %Member{} = member -> {:ok, member}
      nil -> {:error, :member_not_found}
    end
  end

  @spec member_search_method({Guild.id(), [User.t()], String.t()}) ::
          {Guild.id(), atom, Snowflake.t() | String.t()}
  def member_search_method({guild, mentions, full_name}) do
    cond do
      mentions != [] ->
        {guild, :id, hd(mentions).id}

      full_name =~ ~r/^\d+$/ ->
        {guild, :id, String.to_integer(full_name)}

      full_name =~ ~r/#\d{4}$/ ->
        {guild, :tag, full_name}

      true ->
        {guild, :display_name, full_name}
    end
  end

  @spec get_member({Guild.id(), atom, Snowflake.t() | String.t()}) ::
          {:ok, Member.t()} | {:error, atom}
  def get_member({guild, key, value}) do
    case GuildCache.select(guild, & &1.members) do
      {:ok, members} when key == :id ->
        case members[value] do
          %Member{} = member -> {:ok, member}
          nil -> {:error, :member_not_found}
        end

      {:ok, members} when key == :display_name ->
        members
        |> find_member(&(&1.user.username == value))
        |> case do
          {:ok, _member} = result -> result
          {:error, :member_not_found} -> find_member(members, &(&1.nick == value))
        end

      {:ok, members} when key == :tag ->
        [name, disc] = Regex.run(~r/^(.+)#(\d{4})$/, value, capture: :all_but_first)
        find_by_tag = &(&1.user.username == name and &1.user.discriminator == disc)
        find_member(members, find_by_tag)

      {:ok, members} ->
        find_member(members, &(Map.get(&1.user, key) == value))

      {:error, _reason} = error ->
        error
    end
  end

  @spec get_member(Message.t(), non_neg_integer) :: {:ok, Member.t()} | {:error, atom}
  def get_member(%{guild_id: guild_id, content: content, mentions: mentions} = message, position) do
    full_name =
      content
      |> String.split()
      |> (&Enum.slice(&1, position..length(&1))).()
      |> Enum.join(" ")

    cond do
      guild_id == nil ->
        {:error, :requires_guild_context}

      full_name == "" ->
        {:error, :no_identifier_given}

      true ->
        {message.guild_id, mentions, full_name}
        |> member_search_method()
        |> get_member()
    end
  end
end
