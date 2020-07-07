defmodule Curie.Help do
  use Curie.Commands

  import IEx.Helpers, only: [r: 1]

  alias Curie.Help.Info
  alias Nostrum.Api

  @check_typo ~w/curie currency help/

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
  def command({"help", @owner = %{channel_id: channel, id: message}, ["r"]}) do
    r(Info)
    Api.create_reaction(channel, message, "✅")
  end

  @impl Curie.Commands
  def command({"help", message, []}) do
    """
    => Curie's commands

    #{
      Enum.reduce(Info.command_list(), nil, fn command, acc ->
        case {Info.command(command), acc} do
          {%{short: nil}, _acc} -> acc
          {%{short: description}, nil} -> "**#{@prefix <> command}** - #{description}"
          {%{short: description}, acc} -> acc <> "\n**#{@prefix <> command}** - #{description}"
        end
      end)
    }

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
    case Curie.check_typo(command, Info.command_list()) do
      nil ->
        Curie.embed(message, "Command not recognized", "red")

      match ->
        "Command → **#{@prefix <> match}**\n\n" <> Info.command(match).long
        |> (&Curie.embed(message, &1, "green")).()
    end
  end

  @impl Curie.Commands
  def command(call) do
    Commands.check_typo(call, @check_typo, &command/1)
  end
end
