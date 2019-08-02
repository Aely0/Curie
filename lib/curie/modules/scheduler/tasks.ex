defmodule Curie.Scheduler.Tasks do
  import Crontab.CronExpression
  import Ecto.Query, only: [from: 2]
  import Nostrum.Struct.Embed

  alias Nostrum.Api
  alias Nostrum.Cache.PresenceCache
  alias Nostrum.Struct.{Guild, User}

  alias Curie.Currency
  alias Curie.Data.{Balance, Overwatch, Status}
  alias Curie.Data

  alias Crontab.CronExpression

  @overwatch Application.get_env(:curie, :channels)[:overwatch]
  @shadowmere 90_579_372_049_723_392

  @spec get :: %{CronExpression.t() => [function] | function}
  def get do
    %{
      ~e[0] => [
        &curie_balance_decay/0,
        &member_balance_gain/0,
        &set_status/0
      ],
      ~e[0 0] => [
        &curie_balance_gain/0,
        &prune/0
      ]
    }
  end

  @spec apply_gain({User.id(), Guild.id()}) :: :ok
  def apply_gain({id, guild}) do
    with {:ok, %{status: status}} <- PresenceCache.get(id, guild) do
      if status == :online or (status != :offline and Enum.random(1..10) == 10),
        do: Currency.change_balance(:add, id, 1)
    end

    :ok
  end

  @spec member_balance_gain :: :ok
  def member_balance_gain do
    {:ok, curie_id} = Curie.my_id()

    query =
      from(b in Balance,
        select: {b.member, b.guild},
        where: b.value < 300 and b.member != ^curie_id
      )

    query
    |> Data.all()
    |> Enum.each(&apply_gain/1)

    :ok
  end

  @spec curie_balance_gain :: :ok
  def curie_balance_gain do
    with {:ok, id} <- Curie.my_id(),
         %{value: balance} <- Data.get(Balance, id) do
      cond do
        balance + 10 <= 200 -> Currency.change_balance(:add, id, 10)
        balance in 191..199 -> Currency.change_balance(:replace, id, 200)
        true -> nil
      end
    end

    :ok
  end

  @spec curie_balance_decay :: :ok
  def curie_balance_decay do
    with {:ok, id} <- Curie.my_id(),
         %{value: balance} <- Data.get(Balance, id) do
      cond do
        balance - 10 >= 1000 -> Currency.change_balance(:deduct, id, 10)
        balance in 1001..1009 -> Currency.change_balance(:replace, id, 1000)
        true -> nil
      end
    end

    :ok
  end

  @spec set_status :: :ok
  def set_status do
    # /!\ Given ecto query contains fragment specific to PostgreSQL
    case Data.all(from(s in Status, select: s.message, order_by: fragment("RANDOM()"), limit: 1)) do
      [] -> nil
      [message] -> Api.update_status(:online, message)
    end

    :ok
  end

  @spec prune :: :ok
  def prune do
    with {:ok, %{pruned: count}} when count > 0 <- Api.get_guild_prune_count(@shadowmere, 30) do
      Api.begin_guild_prune(@shadowmere, 30)
    end

    :ok
  end

  # Disabled
  @spec overwatch_patch :: :ok
  def overwatch_patch when @overwatch != nil do
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

    :ok
  end

  # Disabled
  @spec overwatch_twitter :: :ok
  def overwatch_twitter when @overwatch != nil do
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

    :ok
  end
end
