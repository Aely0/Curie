defmodule Curie do
  use Application

  alias Nostrum.Cache.GuildCache

  import Nostrum.Api, only: [bangify: 1]
  import Nostrum.Struct.Embed

  @colors Application.get_env(:curie, :colors)

  def color(name), do: Map.get(@colors, name)

  def time_now, do: Timex.local() |> Timex.format!("%H:%M:%S %d-%m-%Y", :strftime)

  def avatar_url(user),
    do: "https://cdn.discordapp.com/avatars/#{user.id}/#{user.avatar}.webp?size=1024"

  def check_typo(call, commands) do
    {match, similarity} =
      if(is_binary(commands), do: List.wrap(commands), else: commands)
      |> Enum.map(&{&1, call |> String.downcase() |> String.jaro_distance(&1)})
      |> Enum.max_by(fn {_call, similarity} -> similarity end)

    if similarity >= 0.75, do: match
  end

  def embed!(channel, description, color), do: embed(channel, description, color) |> bangify()

  def embed(channel, description, color) do
    channel = if is_map(channel), do: channel.channel_id, else: channel
    color = unless is_integer(color), do: color(color), else: color

    %Nostrum.Struct.Embed{}
    |> put_color(color)
    |> put_description(description)
    |> (&Curie.send(channel, embed: &1)).()
  end

  def send!(channel, options), do: Curie.send(channel, options) |> bangify()

  def send(channel, options, retries \\ 0) do
    channel = if is_map(channel), do: channel.channel_id, else: channel

    case Nostrum.Api.create_message(channel, options) do
      {:ok, _message} = result ->
        result

      {:error, %{status_code: code, message: _response}} = error ->
        if code >= 500 and retries <= 10 do
          Process.sleep(250)
          Curie.send(channel, options, retries + 1)
        else
          error
        end
    end
  end

  def edit!(message, options), do: edit(message, options) |> bangify()

  def edit!(channel_id, message_id, options),
    do: edit(channel_id, message_id, options) |> bangify()

  def edit(%{channel_id: channel_id, message_id: message_id} = _message, options),
    do: edit(channel_id, message_id, options)

  def edit(channel_id, message_id, options, retries \\ 0) do
    case Nostrum.Api.edit_message(channel_id, message_id, options) do
      {:ok, _message} = result ->
        result

      {:error, %{status_code: code, message: _response}} = error ->
        if code >= 500 and retries <= 10 do
          Process.sleep(250)
          edit(channel_id, message_id, options, retries + 1)
        else
          error
        end
    end
  end

  def get(url), do: get(url, [], 0)

  def get(url, headers) when is_list(headers), do: get(url, headers, 0)

  def get(url, headers, retries) do
    case HTTPoison.get(url, [{"Connection", "close"}] ++ headers, follow_redirect: true) do
      {:ok, response} ->
        case response.status_code do
          200 ->
            {200, response}

          code ->
            if code >= 500 and retries < 5 do
              Process.sleep(2000)
              get(url, headers, retries + 1)
            else
              {:failed, Integer.to_string(code)}
            end
        end

      {:error, error} ->
        if retries < 5 do
          Process.sleep(2000)
          get(url, headers, retries + 1)
        else
          {:failed, inspect(error.reason)}
        end
    end
  end

  def unix_to_amount(timestamp) do
    amount = (Timex.local() |> Timex.to_unix()) - timestamp
    {minutes, seconds} = {div(amount, 60), rem(amount, 60)}
    {hours, minutes} = {div(minutes, 60), rem(minutes, 60)}
    {days, hours} = {div(hours, 24), rem(hours, 24)}

    [{"d", days}, {"h", hours}, {"m", minutes}, {"s", seconds}]
    |> Enum.filter(fn {_key, value} -> value != 0 end)
    |> Enum.map_join(", ", fn {key, value} -> to_string(value) <> key end)
  end

  def get_member(%{guild_id: guild, content: content, mentions: mentions} = _message, position) do
    full_name =
      content
      |> String.split()
      |> (&Enum.slice(&1, position..length(&1))).()
      |> Enum.join(" ")

    if guild do
      cond do
        mentions != [] ->
          id = mentions |> hd() |> (& &1.id).()

          GuildCache.get!(guild).members
          |> Enum.find(&(&1.user.id == id))

        match?({_id, ""}, Integer.parse(full_name)) ->
          {id, ""} = Integer.parse(full_name)

          GuildCache.get!(guild).members
          |> Enum.find(&(&1.user.id == id))

        full_name =~ ~r/#\d{4}$/ ->
          name = Regex.replace(~r/#\d{4}$/, full_name, "")
          [disc] = Regex.run(~r/\d{4}$/, full_name)

          GuildCache.get!(guild).members
          |> Enum.find(&(&1.user.username == name and &1.user.discriminator == disc))

        true ->
          GuildCache.get!(guild).members
          |> Enum.find(&(&1.user.username == full_name))
      end
    end
  end

  def start(_type, _args) do
    IO.puts("  == Curie - Nostrum #{Application.spec(:nostrum, :vsn)} ==\n")
    Curie.Supervisor.start_link()
  end
end
