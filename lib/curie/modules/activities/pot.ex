defmodule Curie.Pot do
  use Curie.Commands
  use GenServer

  alias Nostrum.Cache.{ChannelCache, UserCache, Me}
  alias Nostrum.Struct.{Channel, Message, User}

  alias Curie.Data.Balance
  alias Curie.Currency

  @self __MODULE__

  @check_typo ~w/pot add/

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @spec defaults() :: map()
  def defaults do
    %{status: :idle, allow_add: false, value: 0, channel: nil, participants: [], limit: nil}
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
  def handle_cast({:update, new}, state) do
    {:noreply, Map.merge(state, new)}
  end

  @impl true
  def handle_cast({:participant, participant}, state) do
    {:noreply, Map.put(state, :participants, state.participants ++ [participant])}
  end

  @impl true
  def handle_cast(:reset, _state) do
    {:noreply, defaults()}
  end

  @spec announce_start(map(), pos_integer(), pos_integer() | nil) :: no_return()
  def announce_start(%{author: %{username: name}} = message, value, limit) do
    mode = if limit == nil, do: "Regular", else: "Limit"

    ("Pot started by **#{name}**! " <>
       "Join with **!add value**.\n" <>
       "Value: **#{value}#{@tempest}**\n" <>
       "Mode: **#{mode}**\n" <> "Rolling winner in 50-70 seconds!")
    |> (&Curie.embed(message, &1, "dblue")).()
  end

  @spec announce_winner(map(), User.id(), pos_integer(), number()) :: no_return()
  def announce_winner(message, winner, value, chance) do
    winner = UserCache.get!(winner)

    ("Winner of the Pot: **#{winner.username}**\n" <>
       "Amount: **#{value}#{@tempest}**\n" <> "Chance: **#{chance}%**")
    |> (&Curie.embed(message, &1, "yellow")).()
  end

  @spec not_enough_players(map()) :: no_return()
  def not_enough_players(message) do
    [
      "Hey guys! Want to... no...? Ok, I'm used to it... \:(",
      "Did we misprint the address on the invitation again?",
      "You can't lose if there is no one to lose to, smart.",
      "It's ok, I'm here for you. *Sarcasm module test completed with 0 errors.*",
      "Congatulations! You won... 'The Loneliest Person Here' award!",
      "Sometimes, I dream about cheese...",
      "♪ All around me are familiar faces... ♪",
      "♪ You are the one and only... ♪"
    ]
    |> Enum.random()
    |> (&Curie.embed(message, &1 <> "\nNot enough participants, value refunded.", "green")).()
  end

  @spec curie_decision(
          :limit | :regular,
          Channel.id(),
          Balance.value(),
          value :: pos_integer(),
          limit :: pos_integer(),
          [{User.id(), pos_integer()}]
        ) :: no_return()
  def curie_decision(:limit, channel, balance, value, limit, participants) do
    cond do
      balance >= limit and trunc(limit / (limit + value) * 100) >= 50 ->
        Curie.send(channel, content: @prefix <> "add #{limit}")

      balance >= limit and trunc(limit / (limit + value) * 100) >= 20 and length(participants) > 1 ->
        Curie.send(channel, content: @prefix <> "add #{limit}")

      trunc(balance / (balance + value) * 100) >= 50 ->
        Curie.send(channel, content: @prefix <> "add #{balance}")

      trunc(balance / (balance + value) * 100) >= 50 and length(participants) > 1 ->
        Curie.send(channel, content: @prefix <> "add #{balance}")

      true ->
        nil
    end
  end

  def curie_decision(:regular, channel, me, balance, value, participants) do
    cond do
      participants |> Enum.at(0) |> elem(0) == me.id and length(participants) == 1 ->
        nil

      trunc(balance / (balance + value) * 100) in 30..80 ->
        Curie.send(channel, content: @prefix <> "add #{balance}")

      trunc(balance / (balance + value) * 100) >= 80 and trunc(balance / 100 * 50) > 0 ->
        amount = trunc(balance / 100 * 50)
        Curie.send(channel, content: @prefix <> "add #{amount}")

      trunc(balance / (balance + value) * 100) <= 30 and trunc(balance / 100 * 20) > 0 ->
        if Enum.random(1..5) == 5 do
          amount = trunc(balance / 100 * 20)
          Curie.send(channel, content: @prefix <> "add #{amount}")
        end

      true ->
        nil
    end
  end

  @spec curie_join(Channel.id()) :: no_return()
  def curie_join(channel) do
    me = Me.get()
    balance = Currency.get_balance(me.id)
    %{value: value, limit: limit, participants: participants} = GenServer.call(@self, :get)

    cond do
      is_integer(limit) and balance > 0 ->
        curie_decision(:limit, channel, balance, value, limit, participants)

      limit == nil and balance > 0 ->
        curie_decision(:regular, channel, me, balance, value, participants)

      true ->
        nil
    end
  end

  @spec pot(Message.t(), User.id(), pos_integer(), pos_integer() | nil) :: no_return()
  def pot(%{channel_id: channel_id} = message, member, value, limit \\ nil) do
    channel = "#" <> ChannelCache.get!(channel_id).name

    GenServer.cast(
      @self,
      {:update,
       %{
         status: :playing,
         limit: limit,
         value: value,
         channel: channel,
         allow_add: true
       }}
    )

    GenServer.cast(@self, {:participant, {member, value}})
    Currency.change_balance(:deduct, member, value)

    announce_start(message, value, limit)

    time = Enum.random(50..70)

    for remaining <- time..1 do
      if time - 30 == remaining, do: Curie.embed(message, "Rolling in 20-40 seconds.", "dblue")

      if 1 == remaining, do: curie_join(channel_id)
      Process.sleep(1000)
    end

    GenServer.cast(@self, {:update, %{allow_add: false}})
    Curie.embed(message, "Rolling...", "dblue")
    Process.sleep(1000)

    state = GenServer.call(@self, :get)
    state = %{state | participants: Enum.shuffle(state.participants)}

    roll = Enum.random(1..state.value)

    winner =
      Enum.reduce_while(state.participants, 1, fn {id, value}, accumulator ->
        if roll in accumulator..(value + accumulator - 1),
          do: {:halt, id},
          else: {:cont, accumulator + value}
      end)

    winner_total =
      Enum.filter(state.participants, fn {id, _value} -> id == winner end)
      |> Enum.reduce(0, fn {_id, value}, accumulator -> value + accumulator end)

    chance = Float.round(winner_total / state.value * 100, 2)
    chance = if chance == trunc(chance), do: trunc(chance), else: chance

    if chance == 100,
      do: not_enough_players(message),
      else: announce_winner(message, winner, state.value, chance)

    Currency.change_balance(:add, winner, state.value)
    GenServer.cast(@self, :reset)
  end

  @spec handle_event({String.t(), map(), map(), list()}) :: no_return()
  def handle_event({"pot", message, %{status: :playing, channel: channel}, _args}) do
    Curie.embed(message, "Game in progress: " <> channel, "red")
  end

  def handle_event({"add", message, %{status: :idle}, _args}) do
    Curie.embed(message, "No game in progress.", "red")
  end

  def handle_event({_event, %{guild_id: nil} = message, _state, _args}) do
    Curie.embed(message, "Really...? No...", "red")
  end

  def handle_event({_event, message, _state, {nil, _args}}) do
    Curie.embed(message, "Invalid amount.", "red")
  end

  def handle_event({"pot", %{author: %{id: member}} = message, _state, {value, args}}) do
    if args != [] and args |> List.first() |> Curie.check_typo("limit"),
      do: pot(message, member, value, value),
      else: pot(message, member, value)
  end

  def handle_event({"add", %{author: %{id: member}} = message, state, {value, _args}}) do
    member_total =
      state.participants
      |> Enum.filter(fn {id, _value} -> id == member end)
      |> Enum.reduce(0, fn {_id, value}, accumulator -> value + accumulator end)

    value = if value > state.limit, do: state.limit, else: value

    if member_total + value <= state.limit do
      GenServer.cast(@self, {:participant, {member, value}})
      Currency.change_balance(:deduct, member, value)
      GenServer.cast(@self, {:update, %{value: state.value + value}})

      ("**#{message.author.username}** added **#{value}#{@tempest}**. " <>
         "Pot value is now **#{state.value + value}#{@tempest}**.")
      |> (&Curie.embed(message, &1, "lblue")).()
    else
      ("Exceeding limit **#{state.limit}#{@tempest}**. " <>
         "Current amount **(#{member_total}/#{state.limit})**.")
      |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @impl true
  def command({event, %{author: %{id: member}} = message, [value | args]})
      when event in ["pot", "add"] do
    if Currency.whitelisted?(message) do
      value = Currency.value_parse(member, value)
      state = GenServer.call(@self, :get)
      handle_event({event, message, state, {value, args}})
    end
  end

  @impl true
  def command(call) do
    check_typo(call, @check_typo, &command/1)
  end
end
