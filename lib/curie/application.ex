defmodule Curie.Application do
  use Application

  @spec nostrum_git_hash() :: String.t()
  def nostrum_git_hash do
    with {:ok, binary} <- File.read("mix.lock") do
      ~r/nostrum.git", "(\w{7}).+"/
      |> Regex.run(binary, capture: :all_but_first)
      |> List.first()
    end
  end

  @impl true
  def start(_type, _args) do
    children = [
      Curie.Data,
      Curie.MessageCache,
      Curie.Scheduler,
      Curie.Images,
      Curie.Help,
      Curie.ActivitySupervisor,
      Curie.Consumer
    ]

    IO.puts("  == Curie - Nostrum #{nostrum_git_hash()} ==\n")
    Supervisor.start_link(children, strategy: :one_for_one, name: Curie.Supervisor)
  end
end
