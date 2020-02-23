defmodule Curie.Images do
  use Curie.Commands
  use GenServer

  @type image_map :: %{(name :: String.t()) => filename :: String.t()}

  @self __MODULE__

  @check_typo ~w/images/

  @spec start_link(any) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl GenServer
  @spec init(any) :: {:ok, image_map}
  def init(_args) do
    {:ok, get_stored_images()}
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast(:reload, _state) do
    {:noreply, get_stored_images()}
  end

  @spec image_folder :: String.t()
  def image_folder do
    File.cwd!() <> "/assets/images/"
  end

  @spec get_images :: image_map
  def get_images do
    GenServer.call(@self, :get)
  end

  @spec refresh_image_state :: :ok
  def refresh_image_state do
    GenServer.cast(@self, :reload)
  end

  @spec get_stored_images :: image_map
  def get_stored_images do
    image_folder()
    |> File.ls!()
    |> Enum.reduce(%{}, fn file, map ->
      Map.put(map, file |> String.split(".") |> hd(), file)
    end)
  end

  @spec send_match(map()) :: :ok
  def send_match(%{content: content} = message) do
    images = get_images()

    if Map.has_key?(images, content) do
      Curie.send(message, file: image_folder() <> images[content])
    end

    :ok
  end

  @impl Curie.Commands
  def command({"images", @owner = message, ["r"]}) do
    refresh_image_state()
    Curie.embed(message, "Image directory state refreshed", "green")
  end

  @impl Curie.Commands
  def command({"images", message, []}) do
    Curie.embed(message, get_images() |> Map.keys() |> Enum.join(", "), "green")
  end

  @impl Curie.Commands
  def command(call) do
    Commands.check_typo(call, @check_typo, &command/1)
  end

  def handler(message) do
    send_match(message)
  end
end
