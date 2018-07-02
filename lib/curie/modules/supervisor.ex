defmodule Curie.ActivitySupervisor do
  use Supervisor

  @self __MODULE__

  def child_spec(_opts) do
    %{id: @self, type: :supervisor, start: {@self, :start_link, []}}
  end

  def start_link do
    Supervisor.start_link(@self, [], name: @self)
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
