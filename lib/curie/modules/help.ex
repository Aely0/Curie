defmodule Curie.Help do
  use Curie.Commands
  use GenServer

  alias Curie.Data.Help
  alias Curie.Data

  @check_typo ~w/curie currency help/
  @self __MODULE__

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl true
  def init(_args) do
    {:ok, get_commands()}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:reload, _state), do: {:noreply, get_commands()}

  @spec parse(String.t()) :: String.t()
  def parse(content) when is_binary(content), do: String.replace(content, "<prefix>", @prefix)

  @spec parse(%{command: String.t(), description: String.t(), short: String.t()}) ::
          {String.t(), %{description: String.t(), short: String.t()}}
  def parse(%{command: command, description: description, short: short} = _entry),
    do: {command, %{description: parse(description), short: short}}

  @spec get_commands() :: %{
          commands: [String.t()],
          full: %{String.t() => %{description: String.t(), short: String.t() | nil}}
        }
  def get_commands do
    case Data.all(Help) do
      [] ->
        %{commands: [], full: %{}}

      entries ->
        Enum.map(entries, &parse/1)
        |> Enum.into(%{})
        |> (&%{commands: Map.keys(&1), full: &1}).()
    end
  end

  @impl true
  def command({"curie", message, _args}) do
    ("Heya, my name is Curie! I am a Discord bot written in Elixir.\n" <>
       "My purpose here is to accompany members of Shadowmere, \n" <>
       "offering relevant information and playful distractions.\n" <>
       "My duties consist of fetching various content from the web,\n" <>
       "posting notifications, updates and hosting mini-games.\n" <>
       "I also help managing this guild with things like role management,\n" <>
       "tracking changes and mundane maintanace tasks.\n" <>
       "If you want to find out about all the things I can help you with,\n" <>
       "you can use one of my commands called **#{@prefix}help**.\n" <>
       "If you want to look at my source code, you can find it here:\n" <>
       "https://github.com/Andris0/CurieEx")
    |> (&Curie.embed(message, &1, 0x620589)).()
  end

  @impl true
  def command({"currency", message, _args}) do
    ("One of the things I manage here is the Currency System.\n" <>
       "It works like this, you can ask the server owner to\n" <>
       "whitelist your account and when approved, you will\n" <>
       "have a balance tied to your account in form of Tempests #{@tempest}.\n" <>
       "You can use these tempests to partake in my mini-games,\n" <>
       "collect rewards and have your name on the leaderboard.\n" <>
       "Current currency related mini-games are Pots and 21,\n" <>
       "purchasable rewards are guild name color roles.\n" <>
       "Both games need at least 2 players to reach a result.\n" <>
       "I can fill one of the player spots, if it is needed.\n" <>
       "(If I have any tempests myself to spend of course.)\n" <>
       "At the start your balance will be 0, you can obtain them\n" <>
       "from a passive gain by being online during full clock hours.\n" <>
       "Passive gain caps at 300, so you'll actaully have to play\n" <>
       "with some other folk if you want to have enough for a name color.\n" <>
       "Other than that, good luck and don't spend it all in one place!\n" <>
       "(Not like you can spend it anywhere else anyway.)")
    |> (&Curie.embed(message, &1, 0xFFD700)).()
  end

  @impl true
  def command({"help", @owner = message, [call]}) when call == "r" do
    GenServer.cast(@self, :reload)
    Curie.embed(message, "Help module state reloaded.", "green")
  end

  @impl true
  def command({"help", message, []}) do
    %{commands: commands, full: full} = GenServer.call(@self, :get)

    commands
    |> Enum.filter(&(full[&1].short != nil))
    |> Enum.map(&"**#{@prefix <> &1}** - #{full[&1].short}")
    |> Enum.join("\n")
    |> (&("=> Curie's commands\n\n#{&1}\n\n" <>
            "[+] indicates the need of additional\n" <>
            "values for a command to run.\n\n" <>
            "Use **#{@prefix}help command** to see additional information,\n" <>
            "passable values, examples and subcommands\nfor a specific command.")).()
    |> (&Curie.embed(message, &1, "green")).()
  end

  @impl true
  def command({"help", message, [command | _rest]}) do
    %{commands: commands, full: full} = GenServer.call(@self, :get)

    case Curie.check_typo(command, commands) do
      nil ->
        Curie.embed(message, "Command not recognized.", "red")

      match ->
        "Command → **#{@prefix <> match}**\n\n#{full[match].description}"
        |> (&Curie.embed(message, &1, "green")).()
    end
  end

  @impl true
  def command(call), do: check_typo(call, @check_typo, &command/1)
end
