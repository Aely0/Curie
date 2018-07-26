defmodule Curie.Supervisor do
  use Supervisor

  @spec start_link() :: Supervisor.on_start()
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_args) do
    children = [
      Curie.Data,
      Curie.Consumer,
      Curie.Scheduler,
      Curie.Images,
      Curie.Help,
      Curie.ActivitySupervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
