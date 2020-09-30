defmodule Curie.Application do
  use Application

  @spec header :: :ok
  def header do
    case File.read("mix.lock") do
      {:ok, binary} ->
        ~r/nostrum.git", "(\w{7})/
        |> Regex.run(binary, capture: :all_but_first)
        |> List.first()
        |> (&"  == Curie - Nostrum #{&1} ==\n").()

      _no_file ->
        "  == Curie - Nostrum ==\n"
    end
    |> IO.puts()
  end

  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    header()

    children = [
      Curie.Data,
      Curie.Storage,
      Curie.MessageCache,
      Curie.Scheduler,
      Curie.Images,
      Curie.Latency,
      Curie.Stream,
      Curie.ActivitySupervisor,
      Curie.Consumer,
      Curie.Heartbeat
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Curie.Supervisor)
  end
end
