defmodule Curie.Generic do
  use Curie.Commands
  use Bitwise

  alias Nostrum.Cache.GuildCache
  alias Nostrum.Api

  import Nostrum.Struct.Embed

  @check_typo ["felweed", "rally", "details", "cat", "overwatch", "roll", "ping"]
  @roles Application.get_env(:curie, :roles)
  @owner_id @owner.author.id

  @impl true
  def command({"eval", @owner = message, code}) do
    result =
      try do
        code
        |> Enum.join(" ")
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
  def command({"purge", %{author: %{id: @owner_id}, channel_id: channel} = _message, [count]}) do
    count
    |> String.to_integer()
    |> (&Api.get_channel_messages!(channel, &1 + 1, {})).()
    |> Enum.map(& &1.id)
    |> (&Api.bulk_delete_messages!(channel, &1)).()
  end

  @impl true
  def command({"avatar", @owner = message, [path]}) do
    case File.read(path) do
      {:ok, file} ->
        %{".jpg" => "jpeg", ".png" => "png", ".gif" => "gif"}
        |> (& &1[Path.extname(path)]).()
        |> (&"data:image/#{&1};base64,").()
        |> (&(&1 <> Base.encode64(file))).()
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
        nil ->
          "Member '#{Enum.join(args, " ")}' not found."
          |> (&Curie.embed(message, &1, "red")).()

        %{roles: roles, user: %{id: member, username: name}} ->
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
      end
    end
  end

  @impl true
  def command({"details", %{guild_id: guild} = message, args}) when args != [] do
    case Curie.get_member(message, 1) do
      nil ->
        "Member '#{Enum.join(args, " ")}' not found."
        |> (&Curie.embed(message, &1, "red")).()

      member ->
        details = Curie.Storage.fetch_details(member.user.id)

        status =
          GuildCache.select_all(& &1.presences)
          |> Enum.flat_map(& &1)
          |> Enum.find(&(&1.user.id == member.user.id))
          |> (&if(&1 != nil, do: Atom.to_string(&1.status), else: "offline")).()

        status =
          case status do
            "offline" ->
              if is_integer(details.online),
                do: "Offline for " <> Curie.unix_to_amount(details.online),
                else: details.online

            "dnd" ->
              "Do Not Disturb"

            status ->
              String.capitalize(status)
          end

        spoke =
          if is_integer(details.spoke),
            do: Curie.unix_to_amount(details.spoke) <> " ago",
            else: details.spoke

        roles =
          GuildCache.get!(guild).roles
          |> Enum.filter(&(&1.id in member.roles))
          |> Enum.map_join(", ", & &1.name)
          |> (&if(&1 == "", do: "None", else: &1)).()

        account_created =
          ((member.user.id >>> 22) + 1_420_070_400_000)
          |> Timex.from_unix(:milliseconds)
          |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)

        guild_joined =
          member.joined_at
          |> Timex.parse!("{ISO:Extended}")
          |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)

        description =
          "Display Name: #{if member.nick, do: member.nick, else: member.user.username}\n" <>
            "Member: #{member.user.username}##{member.user.discriminator}\n" <>
            "Status: #{status}\n" <>
            "Last spoke: #{spoke}\n" <>
            "In channel: #{details.channel}\n" <>
            "ID: #{member.user.id}\n" <>
            "Roles: #{roles}\n" <>
            "Guild joined: #{guild_joined}\n" <> "Account created: #{account_created}"

        Curie.embed(message, description, "green")
    end
  end

  @impl true
  def command({"cat", %{channel_id: channel} = message, _args}) do
    Api.start_typing(channel)

    case Curie.get("http://thecatapi.com/api/images/get") do
      {200, %{headers: headers, body: body}} ->
        {_key, "image/" <> type} = List.keyfind(headers, "Content-Type", 0)
        Curie.send(message, file: %{name: "cat." <> type, body: body})

      {:failed, reason} ->
        "Oh no, I was unable to get your kitteh... (#{reason})"
        |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @impl true
  def command({"overwatch", %{channel_id: channel} = message, _args}) do
    Api.start_typing(channel)

    case Curie.get("https://playoverwatch.com/en-us/news/patch-notes/pc") do
      {200, %{body: body, request_url: url}} ->
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

      {:failed, reason} ->
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
  def command(call), do: check_typo(call, @check_typo, &command/1)
end
