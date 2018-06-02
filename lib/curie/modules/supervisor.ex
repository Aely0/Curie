defmodule Curie.ActivitySupervisor do
  use Supervisor

  def child_spec(_opts) do
    %{id: __MODULE__, type: :supervisor, start: {__MODULE__, :start_link, []}}
  end

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    children = [
      Curie.Leaderboard,
      Curie.TwentyOne,
      Curie.Pot
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

end
