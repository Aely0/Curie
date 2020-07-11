defmodule Curie.Generic do
  use Curie.Commands
  use Bitwise

  import Nostrum.Struct.Embed

  alias Curie.Generic.{Details, Dice, Purge}
  alias Nostrum.Api

  @check_typo ~w/felweed rally avatar details cat dog overwatch rust roll ping/
  @roles Application.get_env(:curie, :roles)

  @impl Curie.Commands
  def command({"eval", @owner = message = %{content: @prefix <> "eval" <> code}, [_ | _]}) do
    result =
      try do
        code
        |> String.trim()
        |> String.replace(~r/^```.*\s|```$/, "")
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
      |> (&Curie.send(message, &1)).()
    else
      Curie.send(message, "```elixir\n#{result}```")
    end
  end

  @impl Curie.Commands
  def command({"purge", @owner = message, options}) do
    Purge.clear(message, options)
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

        Curie.embed(message, "Avatar changed", "green")

      {:error, reason} ->
        :file.format_error(reason)
        |> List.to_string()
        |> (&"#{String.capitalize(&1)}.").()
        |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @impl Curie.Commands
  def command({role, %{author: %{id: id}, guild_id: guild, member: member} = message, args})
      when role in ["felweed", "rally"] and args != [] and @roles != nil do
    with {{:ok, author}, :get_author} <-
           {if(member, do: {:ok, member}, else: Curie.get_member({guild, :id, id})), :get_author},
         {true, :author_is_mod} <- {@roles[role].mod_role_id in author.roles, :author_is_mod},
         {{:ok, target}, :get_target} <-
           {Curie.get_member(message, 1), :get_target},
         {false, :target_is_mod} <- {@roles[role].mod_role_id in target.roles, :target_is_mod} do
      action =
        if @roles[role].id in target.roles do
          Api.remove_guild_member_role(guild, target.user.id, @roles[role].id)
          "removed from"
        else
          Api.add_guild_member_role(guild, target.user.id, @roles[role].id)
          "added to"
        end

      "Role #{String.capitalize(role)} #{action} #{target.nick || target.user.username}."
      |> (&Curie.embed(message, &1, "dblue")).()
    else
      {{:error, :member_not_found}, :get_author} ->
        "Unable to validate author."
        |> (&Curie.embed(message, &1, "red")).()

      {false, :author_is_mod} ->
        "Usage restricted to #{String.capitalize(role)} mods."
        |> (&Curie.embed(message, &1, "red")).()

      {{:error, :member_not_found}, :get_target} ->
        "Member '#{Enum.join(args, " ")}' not found."
        |> (&Curie.embed(message, &1, "red")).()

      {true, :target_is_mod} ->
        "Cannot be used on yourself or other moderators."
        |> (&Curie.embed(message, &1, "red")).()

      {{:error, reason}, action} ->
        "Unable to update roles (#{reason} | #{action})."
        |> (&Curie.embed(message, &1, "red")).()
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
        Curie.embed(message, "Member '#{name}' not found", "red")

      {:error, "415"} ->
        Curie.embed(message, "Invalid format for member's avatar", "red")

      {:error, reason} ->
        Curie.embed(message, "Unable to fetch member's avatar (#{reason})", "red")
    end
  end

  @impl Curie.Commands
  def command({"details", %{guild_id: guild_id} = message, args}) when args != [] do
    case Curie.get_member(message, 1) do
      {:ok, member} ->
        Curie.embed(message, Details.get(member, guild_id), "green")

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
             {:ok, %{"file" => link}} <- Jason.decode(body),
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
  def command({"dog", %{channel_id: channel} = message, _args} = call) do
    Api.start_typing(channel)

    with {:ok, %{body: body}} <- Curie.get("https://random.dog/woof.json"),
         {:ok, %{"fileSizeBytes" => size, "url" => url}} when size < 800_000 <-
           Jason.decode(body),
         {:ok, %{body: body}} <- Curie.get(url) do
      Curie.send(message, file: %{name: "dog" <> Path.extname(url), body: body})
    else
      {:ok, %{"fileSizeBytes" => _}} ->
        command(call)

      reason_one ->
        with {:ok, %{body: body}} <- Curie.get("https://dog.ceo/api/breeds/image/random"),
             {:ok, %{"message" => url, "status" => "success"}} <- Jason.decode(body),
             {:ok, %{body: body}} <- Curie.get(url) do
          Curie.send(message, file: %{name: "dog" <> Path.extname(url), body: body})
        else
          reason_two ->
            ("Oh no, I was unable to get your doggo... " <>
               "(#{inspect(reason_one)}, #{inspect(reason_two)})")
            |> (&Curie.embed(message, &1, "red")).()
        end
    end
  end

  @impl Curie.Commands
  def command({"overwatch", %{channel_id: channel} = message, _args}) do
    Api.start_typing(channel)

    with {:ok, %{body: body, request_url: url}} <-
           Curie.get("https://playoverwatch.com/en-us/news/patch-notes/pc"),
         {:ok, html} <- Floki.parse_document(body) do
      patches =
        html
        |> Floki.find(".PatchNotesSideNav-listItem")
        |> Enum.take(5)
        |> Enum.map(fn patch ->
          build = patch |> Floki.find("h3") |> Floki.text()
          id = patch |> Floki.find("a") |> Floki.attribute("href") |> hd()
          date = patch |> Floki.find("p") |> Floki.text()

          date =
            case Timex.parse(date, "{M}/{D}/{YYYY}") do
              {:ok, _} = ok -> ok
              {:error, _} -> Timex.parse(date, "{YYYY}.{M}.{D}.")
            end
            |> case do
              {:ok, date} -> Timex.format!(date, "%B %d, %Y", :strftime)
              {:error, _} -> "#{date} (?)"
            end

          "[#{build} - #{date}](#{url <> id})"
        end)
        |> Enum.join("\n")

      %Nostrum.Struct.Embed{}
      |> put_author("Latest patches:", nil, "https://i.imgur.com/6NBYBSS.png")
      |> put_description(patches)
      |> put_color(Curie.color("white"))
      |> (&Curie.send(message, embed: &1)).()
    else
      {:error, reason} ->
        "Unable to retrieve patch notes. (#{reason})"
        |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @impl Curie.Commands
  def command({"rust", %{channel_id: channel, content: @prefix <> "rust" <> code}, [_ | _]}) do
    Api.start_typing(channel)

    payload =
      %{
        "channel" => "stable",
        "edition" => "2018",
        "code" =>
          code
          |> String.trim()
          |> String.replace(~r/^```.*\s|```$/, "")
          |> (&~s/fn main(){println!("{:?}",{#{&1}});}/).(),
        "crateType" => "bin",
        "mode" => "debug",
        "tests" => false
      }
      |> Jason.encode!()

    case HTTPoison.post("https://play.rust-lang.org/execute", payload, [], recv_timeout: 20_000) do
      {:ok, %{status_code: 200, body: body}} ->
        %{"success" => success, "stdout" => stdout, "stderr" => stderr} = Jason.decode!(body)

        output =
          cond do
            success -> stdout
            String.contains?(stderr, "timeout --signal=KILL") -> "timeout"
            :error -> stderr |> String.split("\n", parts: 2) |> List.last()
          end

        output =
          if String.length(output) > 2000,
            do: (output |> String.split_at(1986) |> elem(0)) <> "...",
            else: output

        case output do
          "timeout" -> Curie.embed(channel, "Task took too long and was killed", "red")
          "()\n" -> Curie.embed(channel, "Success, but result has no output", "green")
          output -> Curie.send(channel, "```rust\n#{output}```")
        end

      {:ok, %{status_code: status_code}} ->
        Curie.embed(channel, "Unsuccessful request (#{status_code})", "red")

      {:error, %{reason: reason}} ->
        Curie.embed(channel, "Failed request (#{inspect(reason)})", "red")
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
  def command({"ping", message, _args}) do
    Curie.send(message, Curie.Latency.get())
  end

  @impl Curie.Commands
  def command(call) do
    Commands.check_typo(call, @check_typo, &command/1)
  end
end
