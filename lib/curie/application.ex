defmodule Curie.Application do
  use Application
  require Logger

  @spec header :: String.t()
  def header do
    version =
      case File.read("mix.lock") do
        {:ok, binary} ->
          ~r/nostrum.git", "(\w{7})/
          |> Regex.run(binary, capture: :all_but_first)
          |> List.first()

        _no_file ->
          nil
      end

    if version,
      do: "  == Curie - Nostrum #{version} ==\n",
      else: "  == Curie - Nostrum ==\n"
  end

  @impl Application
  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    children = [
      Curie.Data,
      Curie.Storage,
      Curie.MessageCache,
      Curie.Scheduler,
      Curie.Images,
      Curie.Help,
      Curie.Latency,
      Curie.ActivitySupervisor,
      Curie.Consumer,
      Curie.Heartbeat
    ]

    IO.puts(header())
    Supervisor.start_link(children, strategy: :one_for_one, name: Curie.Supervisor)
  rescue
    error ->
      Logger.error(inspect(error))
      Process.sleep(10_000)
      System.restart()
      Process.sleep(:infinity)
  end
end
