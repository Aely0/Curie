defmodule Curie.Consumer do
  @moduledoc """
  Discord event consumer.
  """

  use Nostrum.Consumer

  alias Nostrum.Struct.Message
  alias Nostrum.Consumer

  alias Curie.Commands

  @self __MODULE__

  @commands [
    &Curie.Generic.command/1,
    &Curie.Help.command/1,
    &Curie.Images.command/1,
    &Curie.Storage.command/1,
    &Curie.Currency.command/1,
    &Curie.Colors.command/1,
    &Curie.Weather.command/1,
    &Curie.Pot.command/1,
    &Curie.TwentyOne.command/1,
    &Curie.Leaderboard.command/1
  ]

  @handlers %{
    message: [
      &Curie.Images.handler/1,
      &Curie.Storage.handler/1,
      &Curie.MessageCache.handler/1
    ],
    presence: [
      &Curie.Storage.store_details/1,
      &Curie.Storage.status_gather/1,
      &Curie.Stream.stream/1
    ]
  }

  @spec start_link :: no_return
  def start_link do
    Consumer.start_link(@self, name: @self)
  end

  @spec call_commands(Message.t()) :: {:ok, pid} | :pass
  def call_commands(message) do
    if Commands.command?(message),
      do: message |> Commands.parse() |> call_handlers(@commands),
      else: :pass
  end

  @spec call_handlers(Message.t() | tuple, [function]) :: {:ok, pid}
  def call_handlers(payload, handlers) do
    Task.start(fn -> for handler <- handlers, do: handler.(payload) end)
  end

  @impl Nostrum.Consumer
  def handle_event({:READY, _payload, _ws_state}) do
    IO.puts("# Curie: Awake! #{Curie.time_now()}")
    Curie.Scheduler.Tasks.set_status()
  end

  @impl Nostrum.Consumer
  def handle_event({:MESSAGE_CREATE, message, ws_state}) do
    Curie.Latency.update(ws_state)
    call_commands(message)
    call_handlers(message, @handlers.message)
  end

  @impl Nostrum.Consumer
  def handle_event({:MESSAGE_UPDATE, %{content: content} = updated, ws_state})
      when content != nil do
    Curie.Latency.update(ws_state)
    call_commands(updated)
    call_handlers(updated, @handlers.message)
  end

  @impl Nostrum.Consumer
  def handle_event({:PRESENCE_UPDATE, presence, _ws_state}) do
    call_handlers(presence, @handlers.presence)
  end

  @impl Nostrum.Consumer
  def handle_event({:MESSAGE_DELETE, message, _ws_state}) do
    Curie.Log.delete(message)
  end

  @impl Nostrum.Consumer
  def handle_event({:MESSAGE_REACTION_ADD, reaction, _ws_state}) do
    Curie.Leaderboard.handler(reaction)
  end

  @impl Nostrum.Consumer
  def handle_event({:MESSAGE_REACTION_REMOVE, reaction, _ws_state}) do
    Curie.Leaderboard.handler(reaction)
  end

  @impl Nostrum.Consumer
  def handle_event({:GUILD_MEMBER_ADD, {guild_id, member}, _ws_state}) do
    Curie.Log.join(guild_id, member)
  end

  @impl Nostrum.Consumer
  def handle_event({:GUILD_MEMBER_REMOVE, {_guild_id, member}, _ws_state}) do
    Curie.Log.leave(member)
    Curie.Storage.remove(member.user.id)
  end

  @impl Nostrum.Consumer
  def handle_event(_event), do: :pass
end
