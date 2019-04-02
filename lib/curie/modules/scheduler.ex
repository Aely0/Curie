defmodule Curie.Scheduler do
  import Nostrum.Struct.Embed

  alias Nostrum.Cache.PresenceCache
  alias Nostrum.Api

  alias Curie.Currency
  alias Curie.Data.{Balance, Overwatch, Status}
  alias Curie.Data

  @self __MODULE__
  @overwatch Application.get_env(:curie, :channels).overwatch
  @shadowmere 90_579_372_049_723_392

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{id: @self, start: {@self, :start_link, []}}
  end

  @spec start_link() :: Supervisor.on_start()
  def start_link do
    {:ok, pid} = Task.start_link(&scheduler/0)
    Process.register(pid, @self)
    {:ok, pid}
  end

  @spec apply_gain(Balance.t()) :: no_return()
  def apply_gain(%{member: member, value: balance, guild: guild}) do
    with {:ok, %{status: status}} <- PresenceCache.get(member, guild) do
      if (status == :online and balance < 300) or
           (status in [:idle, :dnd] and balance < 300 and Enum.random(1..10) == 10) do
        Currency.change_balance(:add, member, 1)
      end
    end
  end

  @spec member_balance_gain() :: no_return()
  def member_balance_gain do
    {:ok, curie_id} = Curie.my_id()

    Balance
    |> Data.all()
    |> Enum.filter(&(&1.member != curie_id))
    |> Enum.each(&apply_gain/1)
  end

  @spec curie_balance_gain() :: no_return()
  def curie_balance_gain do
    with {:ok, id} <- Curie.my_id(),
         %{value: balance} <- Data.get(Balance, id) do
      cond do
        balance + 10 <= 200 -> Currency.change_balance(:add, id, 10)
        balance in 191..199 -> Currency.change_balance(:replace, id, 200)
        true -> nil
      end
    end
  end

  @spec curie_balance_decay() :: no_return()
  def curie_balance_decay do
    with {:ok, id} <- Curie.my_id(),
         %{value: balance} <- Data.get(Balance, id) do
      cond do
        balance - 10 >= 1000 -> Currency.change_balance(:deduct, id, 10)
        balance in 1001..1009 -> Currency.change_balance(:replace, id, 1000)
        true -> nil
      end
    end
  end

  @spec set_status() :: no_return()
  def set_status do
    case Data.all(Status) do
      [] -> nil
      entries -> Api.update_status(:online, Enum.random(entries).message)
    end
  end

  @spec prune() :: no_return()
  def prune do
    with {:ok, %{pruned: count}} when count > 0 <- Api.get_guild_prune_count(@shadowmere, 30) do
      Api.begin_guild_prune(@shadowmere, 30)
    end
  end

  @spec overwatch_patch() :: no_return()
  def overwatch_patch do
    with {:ok, %{body: body, request_url: url}} <-
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

      if build != stored.build and !(build =~ ~r/\D\.\D/) do
        %Nostrum.Struct.Embed{}
        |> put_author("New patch released!", nil, "https://i.imgur.com/6NBYBSS.png")
        |> put_description("[#{build} - #{date}](#{url <> id})")
        |> put_color(Curie.color("white"))
        |> (&Curie.send!(@overwatch, embed: &1)).()

        stored
        |> Overwatch.changeset(%{build: build})
        |> Data.update()
      end
    end
  end

  @spec overwatch_twitter() :: no_return()
  def overwatch_twitter do
    auth = [{"Authorization", "Bearer " <> Application.get_env(:curie, :twitter)}]
    base = "https://api.twitter.com/1.1/statuses/user_timeline.json"
    params = "?screen_name=PlayOverwatch&count=50&include_rts=false&exclude_replies=true"

    with {:ok, %{body: body}} <- Curie.get(base <> params, auth) do
      %{"id_str" => tweet} = body |> Poison.decode!() |> Enum.take(1) |> hd()
      tweet_url = "https://twitter.com/PlayOverwatch/status/" <> tweet
      stored = Data.one(Overwatch)

      with true <- tweet != stored.tweet,
           {:ok, %{body: body}} <- Curie.get(tweet_url) do
        %{"og:image" => image, "og:description" => description} =
          Floki.find(body, "meta")
          |> Enum.filter(&match?({_, [{"property", _}, {"content", _}], _}, &1))
          |> Enum.reduce(%{}, fn {_, [{_, key}, {_, value}], _}, acc ->
            Map.put(acc, key, value)
          end)

        put_correct_image_type =
          if image =~ ~r/profile_images/,
            do: &put_thumbnail(&1, image),
            else: &put_image(&1, image)

        %Nostrum.Struct.Embed{}
        |> put_author("Overwatch (@PlayOverwatch)", tweet_url, "https://i.imgur.com/F6buGLg.jpg")
        |> put_description(description |> String.trim_leading("“") |> String.trim_trailing("”"))
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

  @spec scheduler() :: no_return()
  def scheduler do
    time = :calendar.local_time()

    # Hourly
    if match?({_, {_, 0, 0}}, time) do
      Task.start(&curie_balance_decay/0)
      Task.start(&member_balance_gain/0)
      Task.start(&set_status/0)
    end

    # Daily
    if match?({_, {0, 0, 0}}, time) do
      Task.start(&curie_balance_gain/0)
      Task.start(&prune/0)
    end

    Process.sleep(1000 - (:millisecond |> System.os_time() |> rem(1000)))
    scheduler()
  end
end
