defmodule Curie.Images do
  use Curie.Commands
  use GenServer

  @type image_map :: %{(name :: String.t()) => filename :: String.t()}

  @self __MODULE__
  @path "resources/images"
  @check_typo ~w/images/

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl GenServer
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

  @spec get_images() :: image_map()
  def get_images do
    GenServer.call(@self, :get)
  end

  @spec refresh_image_state() :: no_return()
  def refresh_image_state do
    GenServer.cast(@self, :reload)
  end

  @spec get_stored_images() :: image_map()
  def get_stored_images do
    @path
    |> File.ls!()
    |> Enum.reduce(%{}, fn file, map ->
      Map.put(map, file |> String.split(".") |> hd(), file)
    end)
  end

  @spec send_match(map()) :: no_return()
  def send_match(%{content: content} = message) do
    images = get_images()

    if Map.has_key?(images, content) do
      Curie.send(message, file: @path <> "/" <> images[content])
    end
  end

  @impl Curie.Commands
  def command({"images", @owner = message, [call]}) when call == "r" do
    refresh_image_state()
    Curie.embed(message, "Image directory state refreshed.", "green")
  end

  @impl Curie.Commands
  def command({"images", message, []}) do
    Curie.embed(message, (get_images() |> Map.keys() |> Enum.join(", ")) <> ".", "green")
  end

  @impl Curie.Commands
  def command(call) do
    check_typo(call, @check_typo, &command/1)
  end

  @spec handler(map()) :: no_return()
  def handler(message) do
    send_match(message)
    super(message)
  end
end
