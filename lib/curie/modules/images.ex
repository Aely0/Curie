defmodule Curie.Images do
  use Curie.Commands
  use GenServer

  alias Nostrum.Struct.Message

  @path "resources/images"
  @check_typo ["images"]
  @self __MODULE__

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl true
  def init(_args) do
    {:ok, get_images()}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:reload, _state), do: {:noreply, get_images()}

  @spec get_images() :: %{files: [String.t()], names: [String.t()]}
  def get_images do
    files = File.ls!(@path)
    names = Enum.map(files, &(String.split(&1, ".", parts: 2) |> hd()))
    %{names: names, files: files}
  end

  @spec send_match(Message.t()) :: Message.t() | nil
  def send_match(%{content: content} = message) do
    images = GenServer.call(@self, :get)
    index = Enum.find_index(images.names, &(content == &1))

    if index do
      Enum.at(images.files, index)
      |> (&Curie.send(message, file: @path <> "/" <> &1)).()
    end
  end

  @impl true
  def command({"images", @owner = message, [call]}) when call == "r" do
    GenServer.cast(@self, :reload)
    Curie.embed(message, "Image directory refreshed.", "green")
  end

  @impl true
  def command({"images", message, []}) do
    GenServer.call(@self, :get)
    |> (&(Enum.join(&1.names, ", ") <> ".")).()
    |> (&Curie.embed(message, &1, "green")).()
  end

  @impl true
  def command(call), do: check_typo(call, @check_typo, &command/1)

  @spec handler(Message.t()) :: term
  def handler(message) do
    send_match(message)
    super(message)
  end
end
