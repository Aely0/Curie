defmodule Curie.Help.Info do
  @moduledoc """
  Command info.
  """

  @prefix Application.compile_env(:curie, :prefix)
  @tempest Application.compile_env(:curie, :tempest)

  @commands ~w/21 ace add avatar balance cat color curie
  currency deck details dog felweed gift help hit images
  lead overwatch ping pot roll rust stand weather/

  @spec command_list() :: [String.t()]
  def command_list, do: @commands

  @spec command(String.t()) :: %{short: String.t() | nil, long: String.t()}
  def command("21") do
    %{
      short: "[+] PvP version of classic 21.",
      long: """
      Classic game of 21 with a modified
      ruleset to allow players to compete with
      each other. Player with the highest card
      value, without going over 21, wins. If
      multiple players have the winning card
      value, amount won is split equally. If
      everyone has the winning value, it is a
      stalemate and players get back the
      amount they have put in. If everyone
      goes over 21, everyone loses, winnings
      go to the void. Value can be a number,
      percentage, keyword 'all' or 'half'. Joining
      players will automatically put the amount
      of Tempests the game was started on.
      All commands apart from creating a
      game and joining need to be sent in a
      DM with curie. Account needs to be whitelisted.

      Warning: **#{@prefix}21** is a contextual command!

      With no active games it will start a game:
      **#{@prefix}21 value**

      With an active game in join phase it will
      add you to the game:
      **#{@prefix}21**

      Example to create:
      **#{@prefix}21 10**
      **#{@prefix}21 10%**
      **#{@prefix}21 all**

      Example to join:
      **#{@prefix}21**

      Related commands: **#{@prefix}hit**, **#{@prefix}stand**, **#{@prefix}ace type**,
      **#{@prefix}deck**
      """
    }
  end

  def command("ace") do
    %{
      short: nil,
      long: """
      Needs to be used in DM with Curie.
      Chooses the value of an Ace card you
      have at hand. Values can be 1 or 11.

      See command **#{@prefix}21** for more info.

      Examples:
      **#{@prefix}ace 1**
      **#{@prefix}ace 11**
      """
    }
  end

  def command("add") do
    %{
      short: nil,
      long: """
      Adds an amount to a currently active pot.
      The amount can be a number, percentage
      or a keyword. If the pot is in limit mode and
      the given value exceeds the limit, the max
      limited value will be put in instead.
      Account needs to be whitelisted.

      See command **#{@prefix}pot** for more info.

      Examples:
      **#{@prefix}add 10**
      **#{@prefix}add all**
      **#{@prefix}add 20%**

      Related commands: **#{@prefix}pot value**
      """
    }
  end

  def command("avatar") do
    %{
      short: "[+] View member's full-sized avatar.",
      long: """
      Retrieves member's full-sized avatar.
      By default, the image format will be webp.
      However, you can also specify the retrieved
      image to be in one of the following
      formats: jpg/png/webp/gif. This is useful
      when member has an animated avatar,
      in which case you can specify the fetched
      avatar to be a gif. Avatar format can be left
      out or specified before the name of the member.
      The member can be looked up by name,
      full Discord tag, mention or account ID.

      Examples:
      **#{@prefix}avatar Curie**
      **#{@prefix}avatar gif Curie**
      """
    }
  end

  def command("balance") do
    %{
      short: "[?] Shows your balance.",
      long: """
      Displays balance of the account
      invoking this command.
      Account needs to be whitelisted.
      Can take keyword **Curie** to display
      Curie's balance.

      Example: **#{@prefix}balance**
      Subcommand example: **#{@prefix}balance Curie**
      """
    }
  end

  def command("cat") do
    %{
      short: "Cats, yay!",
      long: """
      Retrieves a random cat iimage/gif.
      """
    }
  end

  def command("color") do
    %{
      short: "[+] Taste the rainbow!",
      long: """
      Command used to purchase color roles
      with Tempests. Each color purchase costs
      500#{@tempest}. Any previous colors are overwritten.
      Account needs to be whitelisted for
      purchase and color removal.
      Available color list can be found here:
      http://i.imgur.com/BqrVIbn.png

      Example: **#{@prefix}color Haunted**

      Subcommand Examples:
      **#{@prefix}color_preview Haunted**
      **#{@prefix}color_remove**
      """
    }
  end

  def command("curie") do
    %{
      short: "A short paragraph about myself.",
      long: """
      Introducing myself, explaining who I am and
      what I do here in this guild.
      """
    }
  end

  def command("currency") do
    %{
      short: "Info about the currency system.",
      long: """
      Explaining  what the currency system is,
      how it works and what are the currency related activities.
      """
    }
  end

  def command("deck") do
    %{
      short: nil,
      long: """
      Displays the deck used in the last game of 21.

      See command **#{@prefix}21** for more info.

      Example: **#{@prefix}deck**
      """
    }
  end

  def command("details") do
    %{
      short: "[+] Get info about a guild member.",
      long: """
      Displays information about a specific
      guild member. Contains more
      information than what can be found in
      the Discord client interface. Passed value
      can be member's name, full Discord tag,
      mention or account ID.

      Examples:
      **#{@prefix}details Curie**
      **#{@prefix}details Curie#5713**
      """
    }
  end

  def command("dog") do
    %{
      short: "Doggos, yay!",
      long: """
      Retrieves a random dog image/gif/mp4.
      """
    }
  end

  def command("felweed") do
    %{
      short: "[+] For Felweed moderators.",
      long: """
      Adds / Removes role Felweed to / from a member.
      Cannot be used on yourself or other moderators.
      Target member can be a member's name,
      full Discord tag, mention or account ID.

      Examples:
      **#{@prefix}felweed Curie**

      Moderators: TendeRz, Kasiits, Outdoor, Nyrd.
      """
    }
  end

  def command("gift") do
    %{
      short: "[+] Gift your Tempests to someone.",
      long: """
      Gift an amount of your balance to
      someone else. Both you and the target
      member need to be whitelisted. The
      target for the command can be
      member’s name, full Discord tag,
      mention or account ID.

      Example: **#{@prefix}gift 10 Curie**
      """
    }
  end

  def command("help") do
    %{
      short: nil,
      long: """
      This command can be used to find out
      more information about any command
      and its related commands.

      Example: **#{@prefix}help color**
      """
    }
  end

  def command("hit") do
    %{
      short: nil,
      long: """
      Needs to be used in a DM with Curie.
      Takes a card from the deck and adds to
      your card value. If you get an Ace, you
      need to choose its type (1 or 11) with
      command **#{@prefix}ace type** before
      you can continue.

      See command **#{@prefix}21** for more info.

      Example: **#{@prefix}hit**
      """
    }
  end

  def command("images") do
    %{
      short: "Curie's image responses.",
      long: """
      List of Curie's image keywords that Curie
      will respond to with an image or gif. The
      whole message needs to be an exact
      match of the image name.
      """
    }
  end

  def command("lead") do
    %{
      short: "Displays Tempest leaderboard.",
      long: """
      Displays a leaderboard of all members
      that have been whitelisted for currency
      related activities. Leaderboard can be
      interacted with using buttons.
      There can only be one interactable
      leaderboard at a time. Buttons can be
      used to flip pages and refresh data.
      """
    }
  end

  def command("overwatch") do
    %{
      short: "Retrieves a list of Overwatch patches.",
      long: """
      Gets a list of the latest 5 Overwatch patch
      notes and their links in the appropriate
      order.
      """
    }
  end

  def command("ping") do
    %{
      short: "Curie's latency with Discord.",
      long: """
      Displays an amount in milliseconds that
      it took for Discord to acknowledge the
      heartbeat Curie sent to the Discord
      Gateway on the currently active
      connection. This measurement can be
      incorrect in situations when Curie is just
      starting up or having inconsistencies with
      the current connection to Discord.
      """
    }
  end

  def command("pot") do
    %{
      short: "[+] Gamble with care!",
      long: """
      Throw an amount of Tempests into a
      collective pot, winner takes it all.
      The chance to win is proportional to the
      amount you have put in. The winner is
      selected in 10-20 seconds from the start
      of the pot. You can start the pot in a limit
      mode to set a maximum amount a player
      is allowed to put in, limit is determined by
      the amount the pot was started with. You
      can join the pot with command **#{@prefix}add amount**.
      The value of the pot can be a number,
      percentage, keywords 'all' or 'half'.
      Amounts calculated by percentages and
      keywords are relative to your current
      balance. Account needs to be whitelisted.

      Examples:
      **#{@prefix}pot 10**
      **#{@prefix}pot 25%**
      **#{@prefix}pot half limit**

      Related commands: **#{@prefix}add value**
      """
    }
  end

  def command("roll") do
    %{
      short: "[?] Roll some dice.",
      long: """
      Rolls a D100 by default. Accepts dice type as
      the second value. Dice type specification is as follows:
      <dice_count>D<side_count><display_mode>
      Accepted dice count range is 1-1000.
      Accepted dice side range is 1-1000000.
      Display mode is optional and currently accepts
      parameter "E" to also display individual
      dice rolls in addition to the sum.
      If dice count exceeds 200, "E" display
      mode will only show first 200 die rolls.

      Examples:
      **#{@prefix}roll**
      **#{@prefix}roll D20**
      **#{@prefix}roll 2D8**
      **#{@prefix}roll 4D8E**
      """
    }
  end

  def command("rust") do
    %{
      short: "[+] Run Rust code.",
      long: """
      Rust code execution in isolated environment.
      Tasks running longer than 10 seconds will be
      ended abruptly by the host.
      Handled by: https://play.rust-lang.org/

      Examples:
      **#{@prefix}rust std::i32::MAX**
      **#{@prefix}rust use rand::random; (1..=10).map(|_| random::<u8>()).collect::<Vec<u8>>()**
      """
    }
  end

  def command("stand") do
    %{
      short: nil,
      long: """
      Needs to be used in a DM with Curie.
      Changes your status from playing to
      standing with the value you have at hand.

      See command **#{@prefix}21** for more info.

      Example: **#{@prefix}stand**
      """
    }
  end

  def command("weather") do
    %{
      short: "Gets current weather for a location.",
      long: """
      Retrieves current weather for a given
      location. Provided location can be a
      city, street name, region, landmark,
      postal code, coordinates and pretty
      much anything else that describes
      a location. If no location is provided,
      it defaults to "Riga, Latvia".

      Examples:
      **#{@prefix}weather London**
      **#{@prefix}weather Reabrook Ave**
      **#{@prefix}weather 125 Boulevard René Descartes**
      **#{@prefix}weather Statue of Liberty**
      **#{@prefix}weather 40.741895 -73.989308**
      **#{@prefix}weather LV1010**
      """
    }
  end
end
