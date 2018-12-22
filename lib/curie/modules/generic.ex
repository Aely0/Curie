defmodule Curie.Generic do
  use Curie.Commands
  use Bitwise

  import Nostrum.Struct.Embed

  alias Nostrum.Cache.{GuildCache, PresenceCache}
  alias Nostrum.Api

  @check_typo ~w/felweed rally avatar details cat overwatch roll ping/
  @roles Application.get_env(:curie, :roles)

  @impl true
  def command({"eval", @owner = message, code}) do
    result =
      try do
        code
        |> Enum.join(" ")
        |> (&("import IEx.Helpers;" <> &1)).()
        |> Code.eval_string([message: message], __ENV__)
        |> elem(0)
        |> inspect()
      rescue
        error -> inspect(error)
      end

    if String.length(result) > 2000 do
      String.split_at(result, 1984)
      |> elem(0)
      |> (&"```elixir\n#{&1}...```").()
      |> (&Curie.send(message, content: &1)).()
    else
      Curie.send(message, content: "```elixir\n#{result}```")
    end
  end

  @impl true
  def command({"purge", @owner = %{id: id, channel_id: channel}, [count | option]}) do
    if option != [] and option |> hd() |> Curie.check_typo("curie") do
      curie = Curie.my_id()

      count
      |> String.to_integer()
      |> (&Api.get_channel_messages!(channel, &1 + 1)).()
      |> Enum.filter(&(&1.author.id == curie))
      |> Enum.map(& &1.id)
      |> (&[id | &1]).()
      |> (&Api.bulk_delete_messages!(channel, &1)).()
    else
      count
      |> String.to_integer()
      |> (&Api.get_channel_messages!(channel, &1 + 1)).()
      |> Enum.map(& &1.id)
      |> (&Api.bulk_delete_messages!(channel, &1)).()
    end
  end

  @impl true
  def command({"change_avatar", @owner = message, [path]}) do
    case File.read(path) do
      {:ok, file} ->
        %{".jpg" => "jpeg", ".png" => "png", ".gif" => "gif"}
        |> (& &1[Path.extname(path)]).()
        |> (&"data:image/#{&1};base64,").()
        |> Kernel.<>(Base.encode64(file))
        |> (&Api.modify_current_user!(avatar: &1)).()

        Curie.embed(message, "Avatar changed.", "green")

      {:error, reason} ->
        :file.format_error(reason)
        |> List.to_string()
        |> (&"#{String.capitalize(&1)}.").()
        |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @impl true
  def command({role, %{author: %{id: author}, guild_id: guild} = message, args})
      when role in ["felweed", "rally"] and args != [] do
    if author in @roles[role].mods do
      case Curie.get_member(message, 1) do
        {:ok, %{roles: roles, user: %{id: member, username: name}}} ->
          if member in @roles[role].mods do
            "Cannot be used on yourself or other moderators."
            |> (&Curie.embed(message, &1, "red")).()
          else
            action =
              if @roles[role].id in roles do
                Api.remove_guild_member_role(guild, member, @roles[role].id)
                "removed from"
              else
                Api.add_guild_member_role(guild, member, @roles[role].id)
                "added to"
              end

            "Role #{String.capitalize(role)} #{action} #{name}."
            |> (&Curie.embed(message, &1, "dblue")).()
          end

        {:error, _reason} ->
          "Member '#{Enum.join(args, " ")}' not found."
          |> (&Curie.embed(message, &1, "red")).()
      end
    end
  end

  @impl true
  def command({"avatar", %{channel_id: channel} = message, [format | rest] = args}) do
    Api.start_typing(channel)

    format = Curie.check_typo(format, ~w/jpg png webp gif/)
    member_position = if format, do: 2, else: 1
    format_with_default = format || "webp"

    with {:ok, %{user: %{username: username} = user}} <-
           Curie.get_member(message, member_position),
         avatar_url = Curie.avatar_url(user, format_with_default),
         {:ok, %{body: body}} <- Curie.get(avatar_url) do
      Curie.send(message, file: %{name: "#{username}.#{format_with_default}", body: body})
    else
      {:error, :member_not_found} ->
        name = if format, do: Enum.join(rest, " "), else: Enum.join(args, " ")
        Curie.embed(message, "Member '#{name}' not found", "red")

      {:error, "415"} ->
        Curie.embed(message, "Invalid format for member's avatar", "red")

      {:error, reason} ->
        Curie.embed(message, "Unable to fetch member's avatar (#{reason})", "red")
    end
  end

  @impl true
  def command({"details", %{guild_id: guild} = message, args}) when args != [] do
    case Curie.get_member(message, 1) do
      {:ok,
       %{
         nick: nick,
         roles: roles,
         joined_at: joined_at,
         user: %{id: id, username: name, discriminator: disc}
       }} ->
        details = Curie.Storage.fetch_details(id)

        status =
          case PresenceCache.get(id, guild) do
            {:ok, %{status: status}} -> status
            _presence_not_found -> :offline
          end
          |> case do
            :offline ->
              if is_integer(details.online),
                do: "Offline for " <> Curie.unix_to_amount(details.online),
                else: details.online

            :dnd ->
              "Do Not Disturb"

            status ->
              status |> Atom.to_string() |> String.capitalize()
          end

        spoke =
          if is_integer(details.spoke),
            do: Curie.unix_to_amount(details.spoke) <> " ago",
            else: details.spoke

        roles =
          GuildCache.get!(guild).roles
          |> Map.values()
          |> Enum.filter(&(&1.id in roles))
          |> Enum.map_join(", ", & &1.name)
          |> (&if(&1 == "", do: "None", else: &1)).()

        account_created =
          ((id >>> 22) + 1_420_070_400_000)
          |> Timex.from_unix(:milliseconds)
          |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)

        guild_joined =
          if(joined_at, do: joined_at, else: Api.get_guild_member!(guild, id).joined_at)
          |> Timex.parse!("{ISO:Extended}")
          |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)

        description =
          "Display Name: #{if nick, do: nick, else: name}\n" <>
            "Member: #{name}##{disc}\n" <>
            "Status: #{status}\n" <>
            "Last spoke: #{spoke}\n" <>
            "In channel: #{details.channel}\n" <>
            "ID: #{id}\n" <>
            "Roles: #{roles}\n" <>
            "Guild joined: #{guild_joined}\n" <> "Account created: #{account_created}"

        Curie.embed(message, description, "green")

      {:error, _reason} ->
        "Member '#{Enum.join(args, " ")}' not found."
        |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @impl true
  def command({"cat", %{channel_id: channel} = message, _args}) do
    Api.start_typing(channel)

    case Curie.get("http://thecatapi.com/api/images/get") do
      {:ok, %{headers: headers, body: body}} ->
        {_key, "image/" <> type} = List.keyfind(headers, "Content-Type", 0)
        Curie.send(message, file: %{name: "cat." <> type, body: body})

      {:error, reason_one} ->
        with {:ok, %{body: body}} <- Curie.get("http://aws.random.cat/meow"),
             {:ok, %{"file" => link}} <- Poison.decode(body),
             {:ok, %{body: body}} <- Curie.get(link) do
          Curie.send(message, file: %{name: "cat" <> Path.extname(link), body: body})
        else
          reason_two ->
            "Oh no, I was unable to get your kitteh... (#{reason_one}, #{inspect(reason_two)})"
            |> (&Curie.embed(message, &1, "red")).()
        end
    end
  end

  @impl true
  def command({"overwatch", %{channel_id: channel} = message, _args}) do
    Api.start_typing(channel)

    case Curie.get("https://playoverwatch.com/en-us/news/patch-notes/pc") do
      {:ok, %{body: body, request_url: url}} ->
        patches =
          body
          |> Floki.find(".PatchNotesSideNav-listItem")
          |> Enum.take(5)
          |> Enum.map(fn patch ->
            build = patch |> Floki.find("h3") |> Floki.text()
            id = patch |> Floki.find("a") |> Floki.attribute("href") |> hd()

            date =
              patch
              |> Floki.find("p")
              |> Floki.text()
              |> Timex.parse!("{M}/{D}/{YYYY}")
              |> Timex.format!("%B %d, %Y", :strftime)

            "[#{build} - #{date}](#{url <> id})"
          end)
          |> Enum.join("\n")

        %Nostrum.Struct.Embed{}
        |> put_author("Latest patches:", nil, "https://i.imgur.com/6NBYBSS.png")
        |> put_description(patches)
        |> put_color(Curie.color("white"))
        |> (&Curie.send(message, embed: &1)).()

      {:error, reason} ->
        "Unable to retrieve patch notes. (#{reason})"
        |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @impl true
  def command({"roll", %{author: member} = message, _args}) do
    text = "#{member.username} rolls: #{Enum.random(1..100)}"

    %Nostrum.Struct.Embed{}
    |> put_author(text, nil, Curie.avatar_url(member))
    |> put_color(Curie.color("lblue"))
    |> (&Curie.send(message, embed: &1)).()
  end

  @impl true
  def command({"ping", %{heartbeat: %{send: send, ack: ack}} = message, _args}) do
    (ack - send)
    |> Integer.to_string()
    |> String.trim_trailing("0")
    |> (&Curie.send(message, content: &1 <> "ms")).()
  end

  @impl true
  def command(call) do
    check_typo(call, @check_typo, &command/1)
  end
end
