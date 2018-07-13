defmodule Curie.Scheduler do
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Api

  alias Curie.Data.{Balance, Overwatch, Status}
  alias Curie.Data

  import Nostrum.Struct.Embed

  @self __MODULE__

  @shadowmere 90_579_372_049_723_392
  @overwatch 169_835_616_110_903_307
  @proko 197_436_404_886_667_264

  def child_spec(_opts) do
    %{id: @self, start: {@self, :start_link, []}}
  end

  def start_link do
    {:ok, pid} = Task.start_link(fn -> scheduler() end)
    Process.register(pid, @self)
    {:ok, pid}
  end

  def apply_gain(presences, member, value) do
    with %{status: status} <- Enum.find(presences, &(&1.user.id == member)) do
      if (status == :online and value < 300) or
           (status in [:idle, :dnd] and value < 300 and Enum.random(1..10) == 10),
         do: Curie.Currency.change_balance(:add, member, 1)
    end
  end

  def member_balance_gain do
    me = Nostrum.Cache.Me.get().id

    presences =
      GuildCache.select_all(& &1.presences)
      |> Enum.flat_map(& &1)

    Balance
    |> Data.all()
    |> Enum.filter(&(&1.member != me))
    |> Enum.each(&apply_gain(presences, &1.member, &1.value))
  end

  def curie_balance_change(action) do
    id = Nostrum.Cache.Me.get().id
    balance = Data.get(Balance, id).value
    curie_balance_change(action, id, balance)
  end

  def curie_balance_change(:gain, id, balance) do
    cond do
      balance + 10 <= 200 ->
        Curie.Currency.change_balance(:add, id, 10)

      balance in 191..199 ->
        Curie.Currency.change_balance(:replace, id, 200)

      true ->
        nil
    end
  end

  def curie_balance_change(:decay, id, balance) do
    cond do
      balance - 10 >= 1000 ->
        Curie.Currency.change_balance(:deduct, id, 10)

      balance in 1001..1009 ->
        Curie.Currency.change_balance(:replace, id, 1000)

      true ->
        nil
    end
  end

  def set_status do
    case Data.all(Status) do
      [] ->
        nil

      entries ->
        Api.update_status(:online, Enum.random(entries).message)
    end
  end

  def prune do
    {:ok, %{pruned: count}} = Api.get_guild_prune_count(@shadowmere, 30)
    if count > 0, do: Api.begin_guild_prune(@shadowmere, 30)
  end

  def overwatch_patch do
    with {200, %{body: body, request_url: url}} <-
           Curie.get("https://playoverwatch.com/en-us/news/patch-notes/pc") do
      {build, id, date} =
        body
        |> Floki.find(".PatchNotesSideNav-listItem")
        |> (fn [latest | _rest] ->
              build = latest |> Floki.find("h3") |> Floki.text()
              id = latest |> Floki.find("a") |> Floki.attribute("href") |> hd()

              date =
                latest
                |> Floki.find("p")
                |> Floki.text()
                |> Timex.parse!("{M}/{D}/{YYYY}")
                |> Timex.format!("%B %d, %Y", :strftime)

              {build, id, date}
            end).()

      stored = Data.one(Overwatch)

      if build != stored.build do
        embed =
          %Nostrum.Struct.Embed{}
          |> put_author("New patch released!", nil, "https://i.imgur.com/6NBYBSS.png")
          |> put_description("[#{build} - #{date}](#{url <> id})")
          |> put_color(Curie.color("white"))

        Curie.send!(@overwatch, embed: embed)

        with {:ok, channel} <- Api.create_dm(@proko) do
          Curie.send!(channel.id, embed: embed)
        end

        stored
        |> Overwatch.changeset(%{build: build})
        |> Data.update()
      end
    end
  end

  def overwatch_twitter do
    auth = [{"Authorization", "Bearer " <> Application.get_env(:curie, :twitter)}]
    base = "https://api.twitter.com/1.1/statuses/user_timeline.json"
    params = "?screen_name=PlayOverwatch&count=50&include_rts=false&exclude_replies=true"

    with {200, %{body: body}} <- Curie.get(base <> params, auth) do
      %{
        "id_str" => tweet,
        "text" => text,
        "user" => %{
          "name" => name,
          "screen_name" => screen_name,
          "profile_image_url" => profile_image
        },
        "entities" => %{"urls" => [%{"expanded_url" => tweet_url}]}
      } = body |> Poison.decode!() |> Enum.take(1) |> hd()

      stored = Data.one(Overwatch)

      with true <- tweet != stored.tweet,
           {200, %{body: body}} <- Curie.get(tweet_url) do
        {_, [_, {_, media}], _} =
          body
          |> Floki.find("meta")
          |> Enum.find(&(inspect(&1) =~ ~r/"og:image"/))

        put_correct_image_type =
          if media =~ ~r/profile_images/,
            do: &put_thumbnail(&1, media),
            else: &put_image(&1, media)

        %Nostrum.Struct.Embed{}
        |> put_author("#{name} (@#{screen_name})", tweet_url, profile_image)
        |> put_description(text)
        |> put_color(0x1DA1F3)
        |> put_footer("Twitter", "https://i.imgur.com/mQ0fwiR.png")
        |> put_correct_image_type.()
        |> (&Curie.send!(@overwatch, embed: &1)).()

        stored
        |> Overwatch.changeset(%{tweet: tweet})
        |> Data.update()
      end
    end
  end

  def scheduler do
    %{hour: hour, minute: minute, second: second} = Timex.local()

    if second == 0 do
      Task.start(&overwatch_patch/0)
      Task.start(&overwatch_twitter/0)
    end

    if minute == 0 and second == 0 do
      Task.start(fn -> curie_balance_change(:decay) end)
      Task.start(&member_balance_gain/0)
      Task.start(&set_status/0)
    end

    if hour == 0 and minute == 0 and second == 0 do
      Task.start(fn -> curie_balance_change(:gain) end)
      Task.start(&prune/0)
    end

    Process.sleep(1000)
    scheduler()
  end
end
