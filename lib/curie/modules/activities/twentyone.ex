defmodule Curie.TwentyOne do
  use GenServer

  alias Nostrum.Cache.{ChannelCache, UserCache, Me}
  alias Curie.Currency
  alias Nostrum.Api

  import Curie.Pot, only: [not_enough_players: 1]

  @self __MODULE__

  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  def defaults do
    %{
      phase: :idle,
      channel: nil,
      set_value: 0,
      total_value: 0,
      deck: [],
      private_deck: nil,
      last_deck: nil,
      players: %{}
    }
  end

  def init(_args) do
    {:ok, defaults()}
  end

  def handle_call(:get, _from, state), do: {:reply, state, state}

  def handle_call({:pick_card, player}, _from, state) do
    {card, new_deck} = List.pop_at(state.deck, 0, 0)
    state = %{state | deck: new_deck}

    state =
      if card == 1,
        do: update_in(state.players[player].aces, &(&1 + 1)),
        else: update_in(state.players[player].card_value, &(&1 + card))

    card = if card == 1, do: "Ace", else: card
    state = update_in(state.players[player].cards, &(&1 ++ [card]))

    state =
      if state.players[player].card_value > 21,
        do: put_in(state.players[player].status, :busted),
        else: state

    card_value = state.players[player].card_value
    status = state.players[player].status
    {:reply, {card, card_value, status}, state}
  end

  def handle_call({:ace_convert, player, type}, _from, state) do
    state =
      update_in(state.players[player].aces, fn count -> count - 1 end)
      |> (&update_in(&1.players[player].card_value, fn value -> value + type end)).()

    state =
      if state.players[player].card_value > 21,
        do: put_in(state.players[player].status, :busted),
        else: state

    card_value = state.players[player].card_value
    status = state.players[player].status
    {:reply, {card_value, status}, state}
  end

  def handle_cast({:add_player, player}, state) do
    new_player_state = %{cards: [], card_value: 0, aces: 0, status: :playing}
    new_state = put_in(state.players[player], new_player_state)
    {:noreply, new_state}
  end

  def handle_cast({:remove_player, player}, state) do
    {_removed, new_state} = pop_in(state.players[player])
    {:noreply, new_state}
  end

  def handle_cast(:create_deck, state) do
    deck =
      Enum.flat_map(1..9, &List.duplicate(&1, 4))
      |> (&(List.duplicate(10, 16) ++ &1)).()
      |> Enum.shuffle()

    {:noreply, %{state | deck: deck, private_deck: deck}}
  end

  def handle_cast({:update_player_status, player, status}, state),
    do: {:noreply, put_in(state.players[player].status, status)}

  def handle_cast({:update, new}, state), do: {:noreply, Map.merge(state, new)}

  def handle_cast(:reset, state), do: {:noreply, %{defaults() | last_deck: state.private_deck}}

  def curie_ace_update(id) do
    %{players: %{^id => curie}} = GenServer.call(@self, :get)

    type = if curie.card_value + 11 > 21, do: 1, else: 11
    GenServer.call(@self, {:ace_convert, id, type})

    if curie.aces > 1, do: curie_ace_update(id)
  end

  def curie_pick_cards(id) do
    %{players: %{^id => curie}} = GenServer.call(@self, :get)

    if curie.status == :playing do
      cond do
        curie.aces > 0 ->
          curie_ace_update(id)

        curie.card_value < 17 ->
          {card, _, _} = GenServer.call(@self, {:pick_card, id})
          if card == "Ace", do: curie_ace_update(id)

        curie.card_value in 17..21 ->
          GenServer.cast(@self, {:update_player_status, id, :standing})
      end

      curie_pick_cards(id)
    end
  end

  def curie_move_logic do
    id = Me.get().id
    curie_pick_cards(id)
  end

  def curie_join(channel) do
    state = GenServer.call(@self, :get)
    me = Me.get().id

    if state.phase == :joining and Enum.count(state.players) < 5 and
         Curie.Currency.get_balance(me) >= state.set_value,
       do: Curie.send(channel, content: Curie.prefix() <> "21")
  end

  def announce_start(%{author: %{username: member}} = message, value) do
    ("#{member} started a game of 21! " <>
       "Join value is **#{value}**#{Curie.tempest()}\n" <>
       "Use **!21** to join! Join phase ends in 20s!")
    |> (&Curie.embed(message, &1, "dblue")).()
  end

  def send_cards(player, [first, second]) do
    content = "Your cards are #{first}|#{second}.\nYou have 2 minutes to complete your moves!"

    with {:ok, channel} <- Api.create_dm(player),
         {:ok, _message} <- Curie.embed(channel.id, content, "dblue") do
      nil
    else
      _failed -> {player, UserCache.get!(player).username}
    end
  end

  def valid_player_count?(message) do
    state = GenServer.call(@self, :get)

    if Enum.count(state.players) < 2 do
      for player <- Map.keys(state.players) do
        Curie.Currency.change_balance(:add, player, state.set_value)
      end

      GenServer.cast(@self, :reset)
      not_enough_players(message)
      false
    else
      true
    end
  end

  def join_phase(message) do
    for remaining <- 20..1 do
      if remaining == 5, do: curie_join(message.channel_id)
      Process.sleep(1000)
    end

    valid_player_count?(message)
  end

  def starting_cards(message) do
    state = GenServer.call(@self, :get)
    players = Map.keys(state.players)
    me = Me.get().id

    for player <- players, do: for(_ <- 1..2, do: GenServer.call(@self, {:pick_card, player}))

    names =
      players
      |> Enum.map(&UserCache.get!(&1).username)
      |> Enum.map(&("**" <> &1 <> "**"))
      |> Enum.join(", ")

    ("Starting cards have been distributed!\n" <>
       "Players: #{names}.\n" <>
       "Players have 2 minutes to complete their moves!\n" <>
       "Moves have to be done by private messaging Curie.")
    |> (&Curie.embed(message, &1, "lblue")).()

    state = GenServer.call(@self, :get)
    players = List.delete(players, me)

    unreachable =
      Enum.map(players, &send_cards(&1, state.players[&1].cards))
      |> Enum.filter(&(!is_nil(&1)))

    if !Enum.empty?(unreachable) do
      Enum.each(unreachable, fn {player, _} -> GenServer.cast(@self, {:remove_player, player}) end)

      Enum.map(unreachable, fn {_, name} -> name end)
      |> Enum.join(", ")
      |> (&"#{&1} removed - Unreachable.").()
      |> (&Curie.embed(message, &1, "red")).()
    end

    valid_player_count?(message)
  end

  def ready_check(state, list) do
    Map.keys(state.players)
    |> Enum.map(&if &1 not in list and state.players[&1].status != :playing, do: &1)
    |> Enum.filter(&(!is_nil(&1)))
    |> (&(list ++ &1)).()
  end

  def countdown(message, me, timer \\ 120, ready_check \\ []) do
    state = GenServer.call(@self, :get)
    players = Map.keys(state.players)

    if timer == 20 do
      for player <- players do
        if player != me and player not in ready_check do
          with {:ok, channel} <- Api.create_dm(player) do
            "You have 20 seconds to finish your moves."
            |> (&Curie.embed(channel.id, &1, "lblue")).()
          end
        end
      end

      if me in players, do: Task.start(fn -> curie_move_logic() end)
    end

    ready_check = ready_check(state, ready_check)

    if me in players and me not in ready_check and
         Enum.count(state.players) - 1 == length(ready_check),
       do: Task.start(fn -> curie_move_logic() end)

    Process.sleep(1000)

    cond do
      Enum.count(state.players) == length(ready_check) ->
        Curie.embed(message, "All players have made their moves.", "dblue")
        Process.sleep(1000)

      timer <= 0 ->
        Curie.embed(message, "Time has ended!", "dblue")
        Process.sleep(1000)

      true ->
        countdown(message, me, timer - 1, ready_check)
    end
  end

  def results(message) do
    state = GenServer.call(@self, :get)
    players = Map.keys(state.players)

    for player <- players do
      if state.players[player].aces > 0 do
        state =
          update_in(state.players[player].card_value, fn card_value ->
            card_value + state.players[player].aces
          end)

        state = put_in(state.players[player].aces, 0)
        GenServer.cast(@self, {:update, state})
      end
    end

    state = GenServer.call(@self, :get)

    win_value =
      Enum.map(players, &state.players[&1].card_value)
      |> Enum.filter(&(&1 <= 21))
      |> Enum.max(fn -> 0 end)

    winners = Enum.filter(players, &(state.players[&1].card_value == win_value))
    cut = if winners != [], do: trunc(state.total_value / length(winners)), else: 0

    for player <- winners do
      if cut > 0, do: Curie.Currency.change_balance(:add, player, cut)
    end

    results =
      for player <- players do
        name = UserCache.get!(player).username
        cards = Enum.join(state.players[player].cards, ", ")
        card_value = state.players[player].card_value

        status =
          cond do
            length(winners) == length(players) ->
              "Stalemate"

            player in winners ->
              "Won"

            true ->
              "Lost"
          end

        balance =
          if status == "Lost", do: "-#{state.set_value}", else: "+#{cut - state.set_value}"

        change = if status == "Lost", do: -state.set_value, else: cut - state.set_value

        content =
          "**#{name}** [#{cards}], **#{status}** " <>
            "with **#{card_value}**, **#{balance}**#{Curie.tempest()}"

        {content, change}
      end

    results =
      Enum.sort_by(results, &elem(&1, 1), &>=/2)
      |> Enum.map(&elem(&1, 0))
      |> Enum.join("\n")

    Curie.embed(message, "Results are in! Let's see here...\n" <> results, "yellow")
  end

  def join(message, member) do
    %{total_value: total_value, set_value: set_value, players: players} =
      GenServer.call(@self, :get)

    players = Map.keys(players)

    cond do
      member in players ->
        Curie.embed(message, "You are already in.", "red")

      length(players) >= 10 ->
        Curie.embed(message, "All spots are taken.", "red")

      true ->
        GenServer.cast(@self, {:update, %{total_value: total_value + set_value}})
        Curie.Currency.change_balance(:deduct, member, set_value)
        GenServer.cast(@self, {:add_player, member})
        name = UserCache.get!(member).username

        "**#{name}** joined. [#{length(players) + 1}/10]"
        |> (&Curie.embed(message, &1, "lblue")).()
    end
  end

  def start(message, member, value) do
    channel = "#" <> ChannelCache.get!(message.channel_id).name
    me = Me.get().id

    new_state = %{phase: :joining, channel: channel, set_value: value, total_value: value}
    GenServer.cast(@self, {:update, new_state})
    GenServer.cast(@self, {:add_player, member})

    Currency.change_balance(:deduct, member, value)

    announce_start(message, value)

    if join_phase(message) do
      GenServer.cast(@self, :create_deck)

      if starting_cards(message) do
        GenServer.cast(@self, {:update, %{phase: :playing}})
        countdown(message, me)
        results(message)
      end
    end

    GenServer.cast(@self, :reset)
  end

  def has_aces?(%{author: %{id: id}} = message, state) do
    if state.players[id].aces > 0,
      do: Curie.embed(message, "Choose your Ace value before continuing.", "red"),
      else: false
  end

  def can_continue?(%{author: %{id: id}} = _message, state),
    do: Map.has_key?(state.players, id) and state.players[id].status == :playing

  def command({"ace", %{guild_id: guild, author: %{id: id}} = message, words})
      when is_nil(guild) and length(words) >= 2 do
    state = GenServer.call(@self, :get)

    if can_continue?(message, state) do
      cond do
        state.players[id].aces <= 0 ->
          Curie.embed(message, "No Aces to convert.", "red")

        Enum.at(words, 1) not in ["1", "11"] ->
          Curie.embed(message, "Ace can be converted to 1 or 11.", "red")

        true ->
          type = Enum.at(words, 1) |> String.to_integer()
          {card_value, status} = GenServer.call(@self, {:ace_convert, id, type})
          content = "Ace converted to **#{type}**.\nHand value is now **#{card_value}**."
          Curie.embed(message, content, "lblue")
          if status == :busted, do: Curie.embed(message, "Really...? \**sighs* \*", "red")
      end
    end
  end

  def command({"hit", %{guild_id: guild, author: %{id: id}} = message, _words})
      when is_nil(guild) do
    state = GenServer.call(@self, :get)

    if can_continue?(message, state) and !has_aces?(message, state) do
      {card, card_value, status} = GenServer.call(@self, {:pick_card, id})
      status = Atom.to_string(status) |> String.capitalize()
      content = "You received **#{card}**.\n#{status} with **#{card_value}**."
      Curie.embed(message, content, "lblue")
    end
  end

  def command({"stand", %{guild_id: guild, author: %{id: id}} = message, _words})
      when is_nil(guild) do
    state = GenServer.call(@self, :get)

    if can_continue?(message, state) and !has_aces?(message, state) do
      GenServer.cast(@self, {:update_player_status, id, :standing})
      card_value = state.players[id].card_value
      content = "You are now standing with **#{card_value}**."
      Curie.embed(message, content, "lblue")
    end
  end

  def command({"21", %{author: %{id: member}} = message, words}) do
    state = GenServer.call(@self, :get)
    balance = Curie.Currency.get_balance(member)
    value = words |> Enum.at(1) |> Curie.Currency.value_parse(balance)

    cond do
      !Curie.Currency.whitelisted?(message) ->
        nil

      state.phase == :playing ->
        Curie.embed(message, "Game in progress: #{state.channel}", "red")

      is_nil(message.guild_id) ->
        Curie.embed(message, "Uhuh... that's a no.", "red")

      state.phase == :idle and is_nil(value) ->
        Curie.embed(message, "Invalid amount.", "red")

      true ->
        case state.phase do
          :idle ->
            start(message, member, value)

          :joining ->
            join(message, member)
        end
    end
  end

  def command({"deck", message, _words}) do
    %{last_deck: last_deck} = GenServer.call(@self, :get)

    content =
      if last_deck,
        do: "Last 21's deck: Top side -> [#{Enum.join(last_deck, ", ")}]",
        else: "No games were played since last restart."

    Curie.embed(message, content, "green")
  end

  def command({call, message, words}) do
    with {:ok, match} <- Curie.check_typo(call, ["21", "ace", "hit", "stand", "deck"]),
         do: command({match, message, words})
  end

  def handler(message), do: if(Curie.command?(message), do: message |> Curie.parse() |> command())
end
