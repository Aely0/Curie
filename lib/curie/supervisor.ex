defmodule Curie.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    children = [
      {Postgrex, Application.get_env(:curie, :postgrex)},
      Curie.ActivitySupervisor,
      Curie.Scheduler,
      Curie.Consumer,
      Curie.Images,
      Curie.Help
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

end
