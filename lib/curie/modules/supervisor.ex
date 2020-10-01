defmodule Curie.ActivitySupervisor do
  @moduledoc """
  Game activity and leaderboard supervisor.
  """

  use Supervisor

  @type supervisor_init_tuple :: {:supervisor.sup_flags(), [:supervisor.child_spec()]}

  @self __MODULE__

  @spec child_spec(any) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{id: @self, type: :supervisor, start: {@self, :start_link, []}}
  end

  @spec start_link :: Supervisor.on_start()
  def start_link do
    Supervisor.start_link(@self, [], name: @self)
  end

  @impl Supervisor
  @spec init(any) :: {:ok, supervisor_init_tuple} | :ignore
  def init(_args) do
    children = [
      Curie.Leaderboard,
      Curie.TwentyOne,
      Curie.Pot
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
