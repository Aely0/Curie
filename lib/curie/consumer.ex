defmodule Curie.Consumer do
  use Nostrum.Consumer

  @spec start_link() :: no_return()
  def start_link do
    {:ok, pid} = Consumer.start_link(__MODULE__)
    Process.register(pid, __MODULE__)
    {:ok, pid}
  end

  def add_heartbeat(message, ws) do
    Map.put(message, :heartbeat, %{send: ws.last_heartbeat_send, ack: ws.last_heartbeat_ack})
  end

  def message_handlers(message) do
    [
      &Curie.Commands.handler/1,
      &Curie.Help.handler/1,
      &Curie.Images.handler/1,
      &Curie.Storage.handler/1,
      &Curie.Currency.handler/1,
      &Curie.Colors.handler/1,
      &Curie.Pot.handler/1,
      &Curie.TwentyOne.handler/1,
      &Curie.Leaderboard.handler/1
    ]
    |> Enum.each(&Task.start(fn -> &1.(message) end))
  end

  def presence_handlers(presence) do
    [
      &Curie.Storage.store_details/1,
      &Curie.Storage.status_gather/1,
      &Curie.Announcements.stream/1
    ]
    |> Enum.each(&Task.start(fn -> &1.(presence) end))
  end

  def handle_event({:READY, _payload, _ws_state}) do
    IO.puts("# Curie: Awake! #{Curie.time_now()}")
    Curie.Scheduler.set_status()
  end

  def handle_event({:MESSAGE_CREATE, {message}, ws_state}) do
    add_heartbeat(message, ws_state) |> message_handlers()
  end

  def handle_event({:MESSAGE_UPDATE, {updated}, ws_state}) do
    if Map.has_key?(updated, :content) and String.starts_with?(updated.content, Curie.prefix()) do
      add_heartbeat(updated, ws_state) |> message_handlers()
    end
  end

  def handle_event({:PRESENCE_UPDATE, {_guild, _old, new}, _ws_state}) do
    presence_handlers(new)
  end

  def handle_event({:MESSAGE_DELETE, {message}, _ws_state}) do
    Curie.Announcements.delete_log(message)
  end

  def handle_event({:MESSAGE_REACTION_ADD, {reaction}, _ws_state}) do
    Curie.Leaderboard.handler(reaction)
  end

  def handle_event({:MESSAGE_REACTION_REMOVE, {reaction}, _ws_state}) do
    Curie.Leaderboard.handler(reaction)
  end

  def handle_event({:GUILD_MEMBER_ADD, {guild_id, member}, _ws_state}) do
    Curie.Announcements.join_log(guild_id, member)
  end

  def handle_event({:GUILD_MEMBER_REMOVE, {_guild_id, member}, _ws_state}) do
    Curie.Announcements.leave_log(member)
    Curie.Storage.remove(member.user.id)
  end

  def handle_event(_event) do
    :ok
  end
end
