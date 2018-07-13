defmodule Curie.Images do
  use Curie.Commands
  use GenServer

  @path "resources/images"
  @check_typo ["images"]
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

  def send_match(%{content: content} = message) do
    images = GenServer.call(@self, :get)
    index = Enum.find_index(images.names, &(content == &1))

    if index do
      Enum.at(images.files, index)
      |> (&Curie.send(message, file: @path <> "/" <> &1)).()
    end
  end

  def command({"images", @owner = message, [call]}) when call == "r" do
    GenServer.cast(@self, :reload)
    Curie.embed(message, "Image directory refreshed.", "green")
  end

  def command({"images", message, args}) when args == [] do
    GenServer.call(@self, :get)
    |> (&(Enum.join(&1.names, ", ") <> ".")).()
    |> (&Curie.embed(message, &1, "green")).()
  end

  def command(call), do: check_typo(call, @check_typo, &command/1)

  def handler(message) do
    send_match(message)
    super(message)
  end
end
