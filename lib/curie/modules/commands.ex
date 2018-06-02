defmodule Curie.Commands do
  use Bitwise

  alias Nostrum.Cache.GuildCache
  alias Nostrum.Api

  import Nostrum.Struct.Embed

  @roles Application.get_env(:curie, :roles)
  @owner Curie.owner()

  def command({"eval", @owner = message, words}) do
    eval_code = words |> tl() |> Enum.join(" ")

    result =
      try do
        Code.eval_string(eval_code, [message: message, words: words], __ENV__)
        |> elem(0)
        |> inspect()
      rescue
        error -> inspect(error)
      end

    if String.length(result) > 2000 do
      String.split_at(result, 1984)
      |> elem(0)
      |> (&"```elixir\n#{&1}...```").()
      |> (&Curie.send(message.channel_id, content: &1)).()
    else
      Curie.send(message.channel_id, content: "```elixir\n#{result}```")
    end
  end

  def command({"purge", @owner = message, words}) when length(words) == 2 do
    Enum.at(words, 1)
    |> String.to_integer()
    |> (&Api.get_channel_messages!(message.channel_id, &1 + 1, {})).()
    |> Enum.map(& &1.id)
    |> (&Api.bulk_delete_messages!(message.channel_id, &1)).()
  end

  def command({role, message, words}) when role in ["felweed", "rally"] and length(words) >= 2 do
    if message.author.id in @roles[role].mods do
      case Curie.get_member(message, 1) do
        nil ->
          "Member '#{words |> tl() |> Enum.join(" ")}' not found."
          |> (&Curie.embed(message, &1, "red")).()

        member ->
          if member.user.id in @roles[role].mods do
            "Cannot be used on yourself or other moderators."
            |> (&Curie.embed(message, &1, "red")).()
          else
            action =
              if @roles[role].id in member.roles do
                Api.remove_guild_member_role(message.guild_id, member.user.id, @roles[role].id)
                "removed from"
              else
                Api.add_guild_member_role(message.guild_id, member.user.id, @roles[role].id)
                "added to"
              end

            "Role #{String.capitalize(role)} #{action} #{member.user.username}."
            |> (&Curie.embed(message, &1, "dblue")).()
          end
      end
    end
  end

  def command({"details", message, words}) when length(words) >= 2 do
    case Curie.get_member(message, 1) do
      nil ->
        "Member '#{words |> tl() |> Enum.join(" ")}' not found."
        |> (&Curie.embed(message, &1, "red")).()

      member ->
        details = Curie.Storage.fetch_details(member.user.id)

        status =
          GuildCache.select_all(& &1.presences)
          |> Enum.into([])
          |> List.flatten()
          |> Enum.find(&(&1.user.id == member.user.id))
          |> (&if(!is_nil(&1), do: Atom.to_string(&1.status), else: "offline")).()

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
          GuildCache.get!(message.guild_id).roles
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

  def command({"cat", message, _words}) do
    Api.start_typing(message.channel_id)

    case Curie.get("http://thecatapi.com/api/images/get") do
      {200, response} ->
        file =
          List.keyfind(response.headers, "Content-Type", 0)
          |> elem(1)
          |> String.split("/")
          |> (&"#{:os.system_time(:millisecond)}.#{Enum.at(&1, 1)}").()
          |> (&("resources/temporary/" <> &1)).()

        File.write!(file, response.body)
        Curie.send(message.channel_id, file: file)
        File.rm(file)

      {:failed, reason} ->
        "Oh no, I was unable to get your kitteh... (#{reason})"
        |> (&Curie.embed(message, &1, "red")).()
    end
  end

  def command({"overwatch", message, _words}) do
    Api.start_typing(message.channel_id)

    case Curie.get("https://us.forums.blizzard.com/en/overwatch/c/announcements") do
      {200, response} ->
        patches =
          Floki.find(response.body, "[itemprop=itemListElement] a")
          |> Enum.filter(&String.contains?(Floki.text(&1), "Overwatch Patch Notes"))
          |> Enum.take(5)
          |> Enum.map(&{Floki.text(&1), Floki.attribute(&1, "href") |> hd()})
          |> Enum.map(fn {name, link} ->
            "[#{name}](#{"https://us.forums.blizzard.com" <> link})"
          end)
          |> Enum.join("\n")

        %Nostrum.Struct.Embed{}
        |> put_author("Latest Overwatch patches:", nil, "https://i.imgur.com/6NBYBSS.png")
        |> put_description(patches)
        |> put_color(Curie.color("white"))
        |> (&Curie.send(message.channel_id, embed: &1)).()

      {:failed, reason} ->
        "Unable to retrieve patch notes. (#{reason})"
        |> (&Curie.embed(message, &1, "red")).()
    end
  end

  def command({"roll", message, _words}) do
    text = "#{message.author.username} rolls: #{Enum.random(1..100)}"

    %Nostrum.Struct.Embed{}
    |> put_author(text, nil, Curie.avatar_url(message.author))
    |> put_color(Curie.color("lblue"))
    |> (&Curie.send(message.channel_id, embed: &1)).()
  end

  def command({"ping", message, _words}) do
    {send, _} = message.heartbeat.send.microsecond
    {ack, _} = message.heartbeat.ack.microsecond
    ping = Integer.to_string(ack - send) |> String.trim_trailing("0")
    Curie.send(message.channel_id, content: ping <> "ms")
  end

  def command({call, message, words}) do
    registered = ["felweed", "rally", "details", "cat", "overwatch", "roll", "ping"]
    with {:ok, match} <- Curie.check_typo(call, registered), do: command({match, message, words})
  end

  def handler(message), do: if(Curie.command?(message), do: message |> Curie.parse() |> command())
end
