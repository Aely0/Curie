defmodule Curie.Generic do
  use Curie.Commands
  use Bitwise

  import Nostrum.Struct.Embed

  alias Curie.Generic.Dice

  alias Nostrum.Cache.{GuildCache, PresenceCache}
  alias Nostrum.Api

  @check_typo ~w/felweed rally avatar details cat overwatch roll ping/
  @roles Application.get_env(:curie, :roles)

  @impl Curie.Commands
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

  @impl Curie.Commands
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

  @impl Curie.Commands
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

  @impl Curie.Commands
  def command({role, %{author: %{id: author}, guild_id: guild} = message, args})
      when role in ["felweed", "rally"] and args != [] do
    if author in @roles[role].mods do
      case Curie.get_member(message, 1) do
        {:ok, %{nick: nick, roles: roles, user: %{id: member_id, username: username}}} ->
          if member_id in @roles[role].mods do
            "Cannot be used on yourself or other moderators."
            |> (&Curie.embed(message, &1, "red")).()
          else
            action =
              if @roles[role].id in roles do
                Api.remove_guild_member_role(guild, member_id, @roles[role].id)
                "removed from"
              else
                Api.add_guild_member_role(guild, member_id, @roles[role].id)
                "added to"
              end

            "Role #{String.capitalize(role)} #{action} #{nick || username}."
            |> (&Curie.embed(message, &1, "dblue")).()
          end

        {:error, :member_not_found} ->
          "Member '#{Enum.join(args, " ")}' not found."
          |> (&Curie.embed(message, &1, "red")).()

        {:error, reason} ->
          "Unable to update roles (#{reason})."
          |> (&Curie.embed(message, &1, "red")).()
      end
    end
  end

  @impl Curie.Commands
  def command({"avatar", %{channel_id: channel_id} = message, [format | rest] = args}) do
    Api.start_typing(channel_id)

    format = Curie.check_typo(format, ~w/jpg png webp gif/)
    member_position = if format, do: 2, else: 1
    format_with_default = format || "webp"

    with {:ok, %{nick: nick, user: %{id: user_id, username: username}}} <-
           Curie.get_member(message, member_position),
         {:ok, user} <- Api.get_user(user_id),
         avatar_url = Curie.avatar_url(user, format_with_default),
         {:ok, %{body: body}} <- Curie.get(avatar_url) do
      filename = "#{nick || username}.#{format_with_default}"
      Curie.send(message, file: %{name: filename, body: body})
    else
      {:error, :member_not_found} ->
        name = if format, do: Enum.join(rest, " "), else: Enum.join(args, " ")
        Curie.embed(message, "Member '#{name}' not found.", "red")

      {:error, "415"} ->
        Curie.embed(message, "Invalid format for member's avatar.", "red")

      {:error, reason} ->
        Curie.embed(message, "Unable to fetch member's avatar (#{reason}).", "red")
    end
  end

  @impl Curie.Commands
  def command({"details", %{guild_id: guild} = message, args}) when args != [] do
    case Curie.get_member(message, 1) do
      {:ok,
       %{
         nick: nick,
         roles: roles,
         joined_at: joined_at,
         user: %{id: user_id, username: username, discriminator: disc}
       }} ->
        %{
          offline_since: offline_since,
          last_status_change: last_status_change,
          last_status_type: last_status_type,
          spoke: last_spoke,
          channel: in_channel
        } = Curie.Storage.get_details(user_id)

        presence = PresenceCache.get(user_id, guild)

        status =
          case presence do
            {:ok, %{status: :dnd}} ->
              if last_status_change && last_status_type == "dnd",
                do: "Do Not Disturb for " <> Curie.unix_to_amount(last_status_change),
                else: "Do Not Disturb"

            {:ok, %{status: status}} when status != :offline ->
              status_name = status |> Atom.to_string() |> String.capitalize()

              if last_status_change && last_status_type == to_string(status),
                do: status_name <> " for " <> Curie.unix_to_amount(last_status_change),
                else: status_name

            _offline_or_not_found ->
              if offline_since,
                do: "Offline for #{Curie.unix_to_amount(offline_since)}",
                else: "Never seen online"
          end

        activity =
          case presence do
            {:ok, %{game: %{name: name, type: type, timestamps: %{start: start}}}} ->
              %{0 => "Playing ", 1 => "Streaming ", 2 => "Listening to "}[type] <>
                name <> " for " <> Curie.unix_to_amount(trunc(start / 1000), :utc)

            {:ok, %{status: :online}} ->
              "Stuff and things"

            _offline_idle_dnd ->
              [
                "Sailing the 7 seas",
                "Furnishing their evil lair",
                "Dreaming about cheese...",
                "Watching paint dry",
                "Pretending to be a potato",
                "Praising the sun",
                "Doing a barrel roll",
                "Taking a 14h nap"
              ]
              |> Enum.random()
          end

        last_spoke =
          if last_spoke,
            do: Curie.unix_to_amount(last_spoke) <> " ago",
            else: "Never"

        roles =
          GuildCache.get!(guild).roles
          |> Map.values()
          |> Enum.filter(&(&1.id in roles))
          |> Enum.map_join(", ", & &1.name)
          |> (&if(&1 == "", do: "None", else: &1)).()

        account_created =
          ((user_id >>> 22) + 1_420_070_400_000)
          |> Timex.from_unix(:millisecond)
          |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)

        guild_joined =
          (joined_at || Api.get_guild_member!(guild, user_id).joined_at)
          |> Timex.parse!("{ISO:Extended}")
          |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)

        description =
          "Display Name: #{nick || username}\n" <>
            "Member: #{username}##{disc}\n" <>
            "Status: #{status}\n" <>
            "Activity: #{activity}\n" <>
            "Last spoke: #{last_spoke || "Never"}\n" <>
            "In channel: #{in_channel || "None"}\n" <>
            "ID: #{user_id}\n" <>
            "Roles: #{roles}\n" <>
            "Guild joined: #{guild_joined}\n" <> "Account created: #{account_created}"

        Curie.embed(message, description, "green")

      {:error, :member_not_found} ->
        "Member '#{Enum.join(args, " ")}' not found."
        |> (&Curie.embed(message, &1, "red")).()

      {:error, reason} ->
        "Unable to retrieve details (#{reason})."
        |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @impl Curie.Commands
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

  @impl Curie.Commands
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

  @impl Curie.Commands
  def command({"roll", message, args}) do
    case Dice.roll(Enum.at(args, 0, "D100")) do
      {:ok, roll} ->
        Curie.embed(message, Curie.get_display_name(message) <> " " <> roll, "lblue")

      {:error, reason} ->
        Curie.embed(message, reason, "red")
    end
  end

  @impl Curie.Commands
  def command({"ping", %{heartbeat: %{send: send, ack: ack}} = message, _args}) do
    (ack - send)
    |> Integer.to_string()
    |> String.trim_trailing("0")
    |> (&Curie.send(message, content: &1 <> "ms")).()
  end

  @impl Curie.Commands
  def command(call) do
    check_typo(call, @check_typo, &command/1)
  end
end
