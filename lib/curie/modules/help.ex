defmodule Curie.Help do
  use Curie.Commands
  use GenServer

  alias Curie.Data.Help
  alias Curie.Data

  @type command_info :: %{
          commands: [String.t()],
          full: %{String.t() => %{description: String.t(), short: String.t() | nil}}
        }

  @self __MODULE__

  @check_typo ~w/curie currency help/
  @timeout 300_000

  @spec start_link(any) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl GenServer
  @spec init(any) :: {:ok, command_info}
  def init(_args) do
    {:ok, get_stored_commands()}
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast(:reload, _state) do
    {:noreply, get_stored_commands()}
  end

  @spec get_command_info :: command_info
  def get_command_info do
    GenServer.call(@self, :get)
  end

  @spec refresh_help_state :: :ok
  def refresh_help_state do
    GenServer.cast(@self, :reload)
  end

  @spec parse(String.t()) :: String.t()
  def parse(content) when is_binary(content) do
    String.replace(content, "<prefix>", @prefix)
  end

  @spec parse(%{command: String.t(), description: String.t(), short: String.t()}) ::
          {String.t(), %{description: String.t(), short: String.t()}}
  def parse(%{command: command, description: description, short: short}) do
    {command, %{description: parse(description), short: short}}
  end

  @spec get_stored_commands :: command_info
  def get_stored_commands do
    case Data.all(Help, timeout: @timeout) do
      [] ->
        %{commands: [], full: %{}}

      entries ->
        entries
        |> Enum.map(&parse/1)
        |> Enum.into(%{})
        |> (&%{commands: Map.keys(&1), full: &1}).()
    end
  end

  @impl Curie.Commands
  def command({"curie", message, _args}) do
    """
    This is Curie, a Discord bot written in Elixir.
    Source: https://github.com/Andris0/Curie
    """
    |> (&Curie.embed(message, &1, 0x620589)).()
  end

  @impl Curie.Commands
  def command({"currency", message, _args}) do
    """
    Currency system works like this, you can ask the server owner to
    whitelist your account and when approved, you will
    have a balance tied to your account in form of Tempests #{@tempest}.
    You can use these tempests to partake in my mini-games,
    collect rewards and have your name on the leaderboard.
    Current currency related mini-games are Pots and 21,
    purchasable rewards are guild name color roles.
    Both games need at least 2 players to reach a result.
    Curie can fill one of the player spots if it is needed,
    while having enough currency to take the slot.
    At the start your balance will be 0, you can obtain them
    from a passive gain by being online during full clock hours.
    Being online during full hours provides 100% chance
    to get 1 unit of currency, if idle or in dnd mode, you have
    only a 10% chance of gaining 1 unit of currency.
    Passive gain caps at 300, so you'll actaully have to play
    with others if you want to have enough for a name color.
    Other than that, good luck and don't spend it all in one place!
    """
    |> (&Curie.embed(message, &1, 0xFFD700)).()
  end

  @impl Curie.Commands
  def command({"help", @owner = message, [call]}) when call == "r" do
    refresh_help_state()
    Curie.embed(message, "Help module state reloaded.", "green")
  end

  @impl Curie.Commands
  def command({"help", message, []}) do
    %{commands: commands, full: full} = get_command_info()

    commands =
      Enum.filter(commands, &(full[&1].short != nil))
      |> Enum.map(&"**#{@prefix <> &1}** - #{full[&1].short}")
      |> Enum.join("\n")

    """
    => Curie's commands

    #{commands}

    [+] - command requires additional values to run
    [?] - command can take optional values

    Use **#{@prefix}help command** to see additional information,
    passable values, examples and subcommands
    for a specific command.
    """
    |> (&Curie.embed(message, &1, "green")).()
  end

  @impl Curie.Commands
  def command({"help", message, [command | _rest]}) do
    %{commands: commands, full: full} = get_command_info()

    case Curie.check_typo(command, commands) do
      nil ->
        Curie.embed(message, "Command not recognized.", "red")

      match ->
        "Command → **#{@prefix <> match}**\n\n#{full[match].description}"
        |> (&Curie.embed(message, &1, "green")).()
    end
  end

  @impl Curie.Commands
  def command(call) do
    Commands.check_typo(call, @check_typo, &command/1)
  end
end
