defmodule Curie.Heartbeat do
  alias Curie.Data.Heartbeat
  alias Curie.Data

  @self __MODULE__

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{id: @self, start: {@self, :start_link, []}}
  end

  @spec start_link() :: Supervisor.on_start()
  def start_link do
    {:ok, pid} = Task.start_link(&heartbeat/0)
    Process.register(pid, @self)
    {:ok, pid}
  end

  @spec heartbeat() :: no_return()
  def heartbeat do
    time = Timex.now() |> Timex.to_unix()

    (Data.one(Heartbeat) || %Heartbeat{})
    |> Heartbeat.changeset(%{heartbeat: time})
    |> Data.insert_or_update()

    Process.sleep(10_000)
    heartbeat()
  end

  @spec offline_for_more_than?(non_neg_integer()) :: boolean()
  def offline_for_more_than?(threshold) when is_integer(threshold) and threshold > 0 do
    case Data.one(Heartbeat) do
      %{heartbeat: heartbeat} -> Timex.to_unix(Timex.now()) - heartbeat > threshold
      nil -> false
    end
  end
end
