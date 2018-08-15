defmodule Curie.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Curie.Data,
      Curie.Consumer,
      Curie.Scheduler,
      Curie.Images,
      Curie.Help,
      Curie.ActivitySupervisor
    ]

    IO.puts("  == Curie - Nostrum #{Application.spec(:nostrum, :vsn)} ==\n")
    Supervisor.start_link(children, strategy: :one_for_one, name: Curie.Supervisor)
  end
end
