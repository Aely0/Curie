defmodule Curie.Images do
  use GenServer

  @path "resources/images"
  @owner Curie.owner()
  @self __MODULE__

  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  def init(_args) do
    {:ok, get_images()}
  end

  def handle_call(:get, _from, state), do: {:reply, state, state}

  def handle_cast(:reload, _state), do: {:noreply, get_images()}

  def get_images do
    files = File.ls!(@path)
    names = Enum.map(files, &(String.split(&1, ".", parts: 2) |> hd()))
    %{names: names, files: files}
  end

  def send_match(message) do
    images = GenServer.call(@self, :get)
    index = Enum.find_index(images.names, &(message.content == &1))

    if index do
      Enum.at(images.files, index)
      |> (&Curie.send(message.channel_id, file: @path <> "/" <> &1)).()
    end
  end

  def command({"images", message, words}) when length(words) == 1 do
    images = GenServer.call(@self, :get)
    names = Enum.join(images.names, ", ") <> "."
    Curie.embed(message, names, "green")
  end

  def command({"images", message, words}) when length(words) >= 2 do
    subcommand({Enum.at(words, 1), message, words})
  end

  def command({call, message, words}) do
    with {:ok, match} <- Curie.check_typo(call, "images"), do: command({match, message, words})
  end

  def subcommand({"reload", @owner = message, _words}) do
    GenServer.cast(@self, :reload)
    Curie.embed(message, "Images reloaded.", "green")
  end

  def subcommand({call, message, words}) do
    with {:ok, match} <- Curie.check_typo(call, "reload"), do: subcommand({match, message, words})
  end

  def handler(message) do
    if(Curie.command?(message), do: message |> Curie.parse() |> command())
    send_match(message)
  end
end
