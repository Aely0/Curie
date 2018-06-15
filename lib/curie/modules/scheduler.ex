defmodule Curie.Scheduler do
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Api

  alias Curie.Data.{Balance, Overwatch, Status}
  alias Curie.Data

  import Nostrum.Struct.Embed

  @shadowmere 90_579_372_049_723_392
  @overwatch 169_835_616_110_903_307
  @proko 197_436_404_886_667_264

  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  def start_link do
    {:ok, pid} = Task.start_link(fn -> scheduler() end)
    Process.register(pid, __MODULE__)
    {:ok, pid}
  end

  def apply_gain(presences, member, value) do
    case Enum.find(presences, &(&1.user.id == member)) do
      %{game: _, status: status, user: _} ->
        cond do
          status == :online and value < 300 ->
            Curie.Currency.change_balance(:add, member, 1)

          status in [:idle, :dnd] and value < 300 ->
            if Enum.random(1..10) == 10 do
              Curie.Currency.change_balance(:add, member, 1)
            end

          true ->
            nil
        end

      nil ->
        nil
    end
  end

  def member_balance_gain do
    presences =
      GuildCache.select_all(& &1.presences)
      |> Enum.into([])
      |> List.flatten()

    Balance
    |> Data.all()
    |> Enum.filter(&(&1.member != Nostrum.Cache.Me.get().id))
    |> Enum.each(&apply_gain(presences, &1.member, &1.value))
  end

  def curie_balance_change(action) do
    me = Nostrum.Cache.Me.get().id
    value = Data.get(Balance, me).value

    case action do
      :gain ->
        cond do
          value + 10 <= 200 ->
            Curie.Currency.change_balance(:add, me, 10)

          value in 191..199 ->
            Curie.Currency.change_balance(:replace, me, 200)

          true ->
            nil
        end

      :decay ->
        cond do
          value - 10 >= 1000 ->
            Curie.Currency.change_balance(:deduct, me, 10)

          value in 1001..1009 ->
            Curie.Currency.change_balance(:replace, me, 1000)

          true ->
            nil
        end
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

  def new_overwatch_patch do
    forums = "https://us.forums.blizzard.com/en/overwatch/c/announcements"

    with {200, response} <- Curie.get(forums) do
      {name, link} =
        Floki.find(response.body, "[itemprop=itemListElement] a")
        |> Enum.filter(&String.contains?(Floki.text(&1), "Overwatch Patch Notes"))
        |> (fn [latest | _rest] ->
              {Floki.text(latest), Floki.attribute(latest, "href") |> hd()}
            end).()

      [date] = Regex.run(~r/\w+ \d{1,2}, \d{4}/, name)

      stored =
        case Data.one(Overwatch) do
          nil ->
            %Overwatch{date: nil}

          stored ->
            stored
        end

      if date != stored.date do
        embed =
          %Nostrum.Struct.Embed{}
          |> put_author("New Overwatch patch released!", nil, "https://i.imgur.com/6NBYBSS.png")
          |> put_description("[#{name}](#{"https://us.forums.blizzard.com" <> link})")
          |> put_color(Curie.color("white"))

        Curie.send!(@overwatch, embed: embed)

        with {:ok, channel} <- Api.create_dm(@proko) do
          Curie.send!(channel.id, embed: embed)
        end

        stored
        |> Overwatch.changeset(%{date: date})
        |> Data.insert_or_update()
      end
    end
  end

  def prune, do: Api.begin_guild_prune(@shadowmere, 30)

  def scheduler do
    now = Timex.local()

    if now.second == 0 do
      Task.start(&new_overwatch_patch/0)
    end

    if now.minute == 0 and now.second == 0 do
      Task.start(fn -> curie_balance_change(:decay) end)
      Task.start(&member_balance_gain/0)
      Task.start(&set_status/0)
    end

    if now.hour == 0 and now.minute == 0 and now.second == 0 do
      Task.start(fn -> curie_balance_change(:gain) end)
      Task.start(&prune/0)
    end

    Process.sleep(1000)
    scheduler()
  end
end
