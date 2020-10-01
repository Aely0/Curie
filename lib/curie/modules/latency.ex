defmodule Curie.Latency do
  @moduledoc """
  Discord's websocket connection latency.
  """

  use GenServer

  alias Nostrum.Struct.WSState

  @self __MODULE__

  @spec child_spec(any) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{id: @self, start: {@self, :start_link, []}}
  end

  @spec start_link :: GenServer.on_start()
  def start_link do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl GenServer
  @spec init(any) :: {:ok, nil}
  def init(_args) do
    {:ok, nil}
  end

  @impl GenServer
  def handle_call(:get, _from, nil) do
    {:reply, "No info yet.", nil}
  end

  @impl GenServer
  def handle_call(:get, _from, %{sent: sent, acknowledged: ack} = state) do
    {:reply, "#{DateTime.diff(ack, sent, :millisecond)}ms", state}
  end

  @impl GenServer
  def handle_cast({:update, %{last_heartbeat_send: sent, last_heartbeat_ack: ack}}, _state) do
    {:noreply, %{sent: sent, acknowledged: ack}}
  end

  @spec update(WSState.t()) :: :ok
  def update(ws_state) do
    GenServer.cast(@self, {:update, ws_state})
  end

  @spec get :: String.t()
  def get do
    GenServer.call(@self, :get)
  end
end
