defmodule Curie.TwentyOne do
  use Curie.Commands
  use GenServer

  import Curie.Pot, only: [not_enough_players: 1]

  alias Nostrum.Struct.{Channel, User}
  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Cache.ChannelCache
  alias Nostrum.Api

  alias Curie.{Currency, Storage}

  @type player_status :: :playing | :standing | :busted
  @type card_value_total :: pos_integer()
  @type card :: 2..10 | String.t()
  @type ace_type :: 1 | 11

  @self __MODULE__

  @check_typo ~w/21 ace hit stand deck/

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @spec defaults() :: map()
  def defaults do
    %{
      guild_id: nil,
      phase: :idle,
      channel_name: nil,
      set_value: 0,
      total_value: 0,
      deck: [],
      private_deck: nil,
      last_deck: nil,
      players: %{}
    }
  end

  @impl true
  def init(_args) do
    {:ok, defaults()}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
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

  @impl true
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

  @impl true
  def handle_cast({:add_player, player}, state) do
    new_player_state = %{cards: [], card_value: 0, aces: 0, status: :playing}
    new_state = put_in(state.players[player], new_player_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remove_player, player}, state) do
    {_removed, new_state} = pop_in(state.players[player])
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:create_deck, state) do
    deck =
      Enum.flat_map(1..9, &List.duplicate(&1, 4))
      |> Kernel.++(List.duplicate(10, 16))
      |> Enum.shuffle()

    {:noreply, %{state | deck: deck, private_deck: deck}}
  end

  @impl true
  def handle_cast({:update_player_status, player, status}, state) do
    {:noreply, put_in(state.players[player].status, status)}
  end

  @impl true
  def handle_cast({:update, new}, state) do
    {:noreply, Map.merge(state, new)}
  end

  @impl true
  def handle_cast(:reset, state) do
    {:noreply, %{defaults() | last_deck: state.private_deck}}
  end

  @spec get_state() :: map()
  def get_state do
    GenServer.call(@self, :get)
  end

  @spec pick_card(User.id()) :: {card(), card_value_total(), player_status()}
  def pick_card(player) do
    GenServer.call(@self, {:pick_card, player})
  end

  @spec ace_convert(User.id(), ace_type()) :: {card_value_total(), player_status()}
  def ace_convert(player, type) do
    GenServer.call(@self, {:ace_convert, player, type})
  end

  @spec add_player(User.id()) :: no_return()
  def add_player(player) do
    GenServer.cast(@self, {:add_player, player})
  end

  @spec remove_player(User.id()) :: no_return()
  def remove_player(player) do
    GenServer.cast(@self, {:remove_player, player})
  end

  @spec create_deck() :: no_return()
  def create_deck do
    GenServer.cast(@self, :create_deck)
  end

  @spec update_player_status(User.id(), player_status()) :: no_return()
  def update_player_status(player, status) do
    GenServer.cast(@self, {:update_player_status, player, status})
  end

  @spec update_state(map()) :: no_return()
  def update_state(new_state) do
    GenServer.cast(@self, {:update, new_state})
  end

  @spec reset_state() :: no_return()
  def reset_state do
    GenServer.cast(@self, :reset)
  end

  @spec curie_ace_update(User.id()) :: no_return()
  def curie_ace_update(id) do
    %{players: %{^id => curie}} = get_state()

    type = if curie.card_value + 11 > 21, do: 1, else: 11
    ace_convert(id, type)

    if curie.aces > 1, do: curie_ace_update(id)
  end

  @spec curie_pick_cards(User.id()) :: no_return()
  def curie_pick_cards(id) do
    %{players: %{^id => curie}} = get_state()

    if curie.status == :playing do
      cond do
        curie.aces > 0 ->
          curie_ace_update(id)

        curie.card_value < 17 ->
          {card, _, _} = pick_card(id)
          if card == "Ace", do: curie_ace_update(id)

        curie.card_value in 17..21 ->
          update_player_status(id, :standing)
      end

      curie_pick_cards(id)
    end
  end

  @spec curie_move_logic() :: no_return()
  def curie_move_logic do
    curie_pick_cards(Curie.my_id())
  end

  @spec curie_join(Channel.id()) :: no_return()
  def curie_join(channel_id) do
    state = get_state()

    if state.phase == :joining and Enum.count(state.players) < 5 and
         Currency.get_balance(Curie.my_id()) >= state.set_value do
      Curie.send(channel_id, content: @prefix <> "21")
    end
  end

  @spec announce_start(map(), pos_integer()) :: no_return()
  def announce_start(message, value) do
    ("#{Curie.get_display_name(message)} started a game of 21! " <>
       "Join value is **#{value}**#{@tempest}\n" <> "Use **!21** to join! Join phase ends in 20s!")
    |> (&Curie.embed(message, &1, "dblue")).()
  end

  @spec send_cards(User.id(), [card()]) :: :ok | {User.id(), Member.nick() | User.username()}
  def send_cards(player, [first, second]) do
    content = "Your cards are #{first}|#{second}.\nYou have 2 minutes to complete your moves!"

    with {:ok, %{id: channel_id}} <- Api.create_dm(player),
         {:ok, _message} <- Curie.embed(channel_id, content, "dblue") do
      :ok
    else
      _failed ->
        %{guild_id: guild_id} = get_state()
        {player, Curie.get_display_name(guild_id, player)}
    end
  end

  @spec valid_player_count?(map()) :: boolean()
  def valid_player_count?(message) do
    state = get_state()

    if Enum.count(state.players) < 2 do
      for player <- Map.keys(state.players) do
        Currency.change_balance(:add, player, state.set_value)
      end

      reset_state()
      not_enough_players(message)
    end
    |> (&(!&1)).()
  end

  @spec join_phase(map()) :: boolean()
  def join_phase(%{channel_id: channel_id} = message) do
    for remaining <- 20..1 do
      if remaining == 5, do: curie_join(channel_id)
      Process.sleep(1000)
    end

    valid_player_count?(message)
  end

  @spec starting_cards(map()) :: boolean()
  def starting_cards(%{guild_id: guild_id} = message) do
    state = get_state()
    players = Map.keys(state.players)

    for player <- players, do: for(_ <- 1..2, do: pick_card(player))

    names =
      players
      |> Enum.map(&Curie.get_display_name(guild_id, &1))
      |> Enum.map(&("**" <> &1 <> "**"))
      |> Enum.join(", ")

    ("Starting cards have been distributed!\n" <>
       "Players: #{names}.\n" <>
       "Players have 2 minutes to complete their moves!\n" <>
       "Moves have to be done by private messaging Curie.")
    |> (&Curie.embed(message, &1, "lblue")).()

    state = get_state()
    players = List.delete(players, Curie.my_id())

    unreachable =
      players
      |> Enum.map(&send_cards(&1, state.players[&1].cards))
      |> Enum.reject(&(&1 == :ok))

    if unreachable != [] do
      Enum.each(unreachable, fn {player, _} -> remove_player(player) end)

      unreachable
      |> Enum.map(fn {_, name} -> name end)
      |> Enum.join(", ")
      |> (&"#{&1} removed - Unreachable.").()
      |> (&Curie.embed(message, &1, "red")).()
    end

    valid_player_count?(message)
  end

  @spec ready_check(map(), [User.id()]) :: [User.id()]
  def ready_check(state, list) do
    Map.keys(state.players)
    |> Enum.map(&if &1 not in list and state.players[&1].status != :playing, do: &1)
    |> Enum.filter(&(&1 != nil))
    |> Kernel.++(list)
  end

  @spec countdown(map(), User.id(), 0..120, [User.id()]) :: no_return()
  def countdown(message, curie, timer \\ 120, ready_check \\ []) do
    state = get_state()
    players = Map.keys(state.players)

    if timer == 20 do
      for player <- players do
        if player != curie and player not in ready_check do
          with {:ok, %{id: channel_id}} <- Api.create_dm(player) do
            "You have 20 seconds to finish your moves."
            |> (&Curie.embed(channel_id, &1, "lblue")).()
          end
        end
      end

      if curie in players, do: Task.start(fn -> curie_move_logic() end)
    end

    ready_check = ready_check(state, ready_check)

    if curie in players and curie not in ready_check and
         Enum.count(state.players) - 1 == length(ready_check) do
      Task.start(fn -> curie_move_logic() end)
    end

    Process.sleep(1000)

    cond do
      Enum.count(state.players) == length(ready_check) ->
        Curie.embed(message, "All players have made their moves.", "dblue")
        Process.sleep(1000)

      timer <= 0 ->
        Curie.embed(message, "Time has ended!", "dblue")
        Process.sleep(1000)

      true ->
        countdown(message, curie, timer - 1, ready_check)
    end
  end

  @spec results(map()) :: no_return()
  def results(%{guild_id: guild_id} = message) do
    state = get_state()
    players = Map.keys(state.players)

    for player <- players do
      if state.players[player].aces > 0 do
        state =
          update_in(state.players[player].card_value, fn card_value ->
            card_value + state.players[player].aces
          end)

        state = put_in(state.players[player].aces, 0)
        update_state(state)
      end
    end

    state = get_state()

    win_value =
      players
      |> Enum.map(&state.players[&1].card_value)
      |> Enum.filter(&(&1 <= 21))
      |> Enum.max(fn -> 0 end)

    winners = Enum.filter(players, &(state.players[&1].card_value == win_value))
    cut = if winners != [], do: trunc(state.total_value / length(winners)), else: 0

    for player <- winners do
      if cut > 0, do: Currency.change_balance(:add, player, cut)
    end

    results =
      for player <- players do
        cards = Enum.join(state.players[player].cards, ", ")
        card_value = state.players[player].card_value
        name = Curie.get_display_name(guild_id, player)

        status =
          cond do
            length(winners) == length(players) -> "Stalemate"
            player in winners -> "Won"
            true -> "Lost"
          end

        balance =
          if status == "Lost", do: "-#{state.set_value}", else: "+#{cut - state.set_value}"

        change = if status == "Lost", do: -state.set_value, else: cut - state.set_value

        content =
          "**#{name}** [#{cards}], **#{status}** " <>
            "with **#{card_value}**, **#{balance}**#{@tempest}"

        {content, change}
      end

    results =
      Enum.sort_by(results, &elem(&1, 1), &>=/2)
      |> Enum.map(&elem(&1, 0))
      |> Enum.join("\n")

    Curie.embed(message, "Results are in! Let's see here...\n" <> results, "yellow")
  end

  @spec join(map(), User.id()) :: no_return()
  def join(message, member_id) do
    %{total_value: total_value, set_value: set_value, players: players} = get_state()

    players = Map.keys(players)

    cond do
      member_id in players ->
        Curie.embed(message, "You are already in.", "red")

      length(players) >= 10 ->
        Curie.embed(message, "All spots are taken.", "red")

      true ->
        update_state(%{total_value: total_value + set_value})
        Currency.change_balance(:deduct, member_id, set_value)
        name = Curie.get_display_name(message)
        add_player(member_id)

        "**#{name}** joined [#{length(players) + 1}/10]"
        |> (&Curie.embed(message, &1, "lblue")).()
    end
  end

  @spec start(map(), User.id(), pos_integer()) :: no_return()
  def start(%{guild_id: guild_id, channel_id: channel_id} = message, member_id, value) do
    channel_name =
      case ChannelCache.get(channel_id) do
        {:ok, %{name: name}} -> "#" <> name
        _not_found -> "an unknown channel"
      end

    update_state(%{
      guild_id: guild_id,
      phase: :joining,
      channel_name: channel_name,
      set_value: value,
      total_value: value
    })

    add_player(member_id)
    Currency.change_balance(:deduct, member_id, value)
    announce_start(message, value)

    if join_phase(message) do
      create_deck()

      if starting_cards(message) do
        update_state(%{phase: :playing})
        countdown(message, Curie.my_id())
        results(message)
      end
    end

    reset_state()
  end

  @spec has_aces?(map(), map()) :: boolean()
  def has_aces?(%{author: %{id: id}} = message, state) do
    if state.players[id].aces > 0 do
      Curie.embed(message, "Choose your Ace value before continuing.", "red")
    end
    |> (&(!!&1)).()
  end

  @spec can_continue?(%{author: %{id: User.id()}}, map()) :: boolean()
  def can_continue?(%{author: %{id: id}}, state) do
    Map.has_key?(state.players, id) and state.players[id].status == :playing
  end

  @spec handle_event({map(), map(), pos_integer() | nil}) :: no_return()
  def handle_event({message, %{phase: :playing, channel_name: channel_name}, _value}) do
    Curie.embed(message, "Game already started in #{channel_name}.", "red")
  end

  def handle_event({%{guild_id: nil} = message, _state, _value}) do
    Curie.embed(message, "Uhuh... that's a no.", "red")
  end

  def handle_event({message, %{phase: :idle}, nil}) do
    Curie.embed(message, "Invalid amount.", "red")
  end

  def handle_event({%{author: %{id: member_id}} = message, %{phase: :idle}, value}) do
    start(message, member_id, value)
  end

  def handle_event({%{author: %{id: member_id}} = message, %{phase: :joining}, _value}) do
    join(message, member_id)
  end

  @impl true
  def command({"deck", message, _args}) do
    %{last_deck: last_deck} = get_state()

    content =
      if last_deck,
        do: "Last 21's deck: Top side -> [#{Enum.join(last_deck, ", ")}]",
        else: "No games were played since last restart."

    Curie.embed(message, content, "green")
  end

  @impl true
  def command({"ace", %{guild_id: guild, author: %{id: member_id}} = message, [value | _rest]})
      when guild == nil do
    state = get_state()

    if can_continue?(message, state) do
      cond do
        state.players[member_id].aces <= 0 ->
          Curie.embed(message, "No Aces to convert.", "red")

        value not in ["1", "11"] ->
          Curie.embed(message, "Ace can be converted to 1 or 11.", "red")

        true ->
          card_type = String.to_integer(value)
          {card_value, status} = ace_convert(member_id, card_type)
          content = "Ace converted to **#{card_type}**.\nHand value is now **#{card_value}**."
          Curie.embed(message, content, "lblue")
          if status == :busted, do: Curie.embed(message, "Really...? \**sighs* \*", "red")
      end
    end
  end

  @impl true
  def command({"hit", %{guild_id: guild, author: %{id: member_id}} = message, _args})
      when guild == nil do
    state = get_state()

    if can_continue?(message, state) and not has_aces?(message, state) do
      {card, card_value, status} = pick_card(member_id)
      status = Atom.to_string(status) |> String.capitalize()
      content = "You received **#{card}**.\n#{status} with **#{card_value}**."
      Curie.embed(message, content, "lblue")
    end
  end

  @impl true
  def command({"stand", %{guild_id: guild, author: %{id: member_id}} = message, _args})
      when guild == nil do
    state = get_state()

    if can_continue?(message, state) and not has_aces?(message, state) do
      update_player_status(member_id, :standing)
      card_value = state.players[member_id].card_value
      content = "You are now standing with **#{card_value}**."
      Curie.embed(message, content, "lblue")
    end
  end

  @impl true
  def command({"21", %{author: %{id: member_id}} = message, [value | _rest]}) do
    if Storage.whitelisted?(message) do
      value = Currency.value_parse(member_id, value)
      state = get_state()
      handle_event({message, state, value})
    else
      Storage.whitelist_message(message)
    end
  end

  @impl true
  def command({"21", message, []}) do
    if Storage.whitelisted?(message),
      do: handle_event({message, get_state(), nil}),
      else: Storage.whitelist_message(message)
  end

  @impl true
  def command(call) do
    check_typo(call, @check_typo, &command/1)
  end
end
