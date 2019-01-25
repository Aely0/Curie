defmodule Curie.MessageCache do
  use GenServer

  import Nostrum.Struct.Snowflake, only: [is_snowflake: 1]

  alias Nostrum.Struct.{Channel, Guild, Message, User}
  alias Nostrum.Api

  @self __MODULE__

  @ignore [Application.get_env(:curie, :owner)]
  @limit 200

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl true
  def init(_args) do
    {:ok, %{id: me}} = Api.get_current_user()
    {:ok, %{:ignore => [me | @ignore]}}
  end

  @impl true
  def handle_cast({:add, %{guild_id: guild, channel_id: channel} = message}, state) do
    {:noreply, add(guild || channel, message, state)}
  end

  @impl true
  def handle_call({:get, container_id, message_id}, _from, state) do
    if Map.has_key?(state, container_id),
      do: {:reply, Enum.find(state[container_id], &(&1.id == message_id)), state},
      else: {:reply, nil, state}
  end

  @impl true
  def handle_call({:get, message_id}, _from, state) do
    state
    |> Map.delete(:ignore)
    |> Enum.map(fn {_container_id, container} ->
      Enum.find(container, &(&1.id == message_id))
    end)
    |> Enum.find(&(&1 != nil))
    |> (&{:reply, &1, state}).()
  end

  @impl true
  def handle_call(:ignore, _from, %{ignore: ignore_list} = state) do
    {:reply, ignore_list, state}
  end

  @spec add(Message.t()) :: no_return()
  defp add(message) do
    GenServer.cast(@self, {:add, message})
  end

  @spec add(Channel.id() | Guild.id(), map(), map()) :: map()
  defp add(container_id, message, state) do
    if Map.has_key?(state, container_id) do
      state[container_id]
      |> prepend(message)
      |> (&%{state | container_id => &1}).()
    else
      Map.put(state, container_id, [message])
    end
  end

  @spec prepend(list(), map()) :: list()
  defp prepend(container, message) do
    if length(container) >= @limit,
      do: [message | Enum.take(container, @limit - 1)],
      else: [message | container]
  end

  @spec ignore?(%{author: %{id: User.id()}}) :: boolean()
  def ignore?(%{author: %{id: member_id}}) do
    member_id in GenServer.call(@self, :ignore)
  end

  @spec ignore?(%{user: %{id: User.id()}}) :: boolean()
  def ignore?(%{user: %{id: member_id}}) do
    member_id in GenServer.call(@self, :ignore)
  end

  @spec get(%{guild_id: Guild.id(), id: Message.id()}) :: map() | nil
  def get(%{guild_id: guild, id: message}) do
    GenServer.call(@self, {:get, guild, message})
  end

  @spec get(%{channel_id: Channel.id(), id: Message.id()}) :: map() | nil
  def get(%{channel_id: direct_message, id: message}) do
    GenServer.call(@self, {:get, direct_message, message})
  end

  @spec get(Message.id()) :: map() | nil
  def get(message_id) when is_snowflake(message_id) do
    GenServer.call(@self, {:get, message_id})
  end

  @spec handler(map()) :: no_return()
  def handler(message) do
    if not ignore?(message) do
      add(message)
    end
  end
end
