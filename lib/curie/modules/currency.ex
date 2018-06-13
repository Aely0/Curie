defmodule Curie.Currency do
  alias Nostrum.Cache.{GuildCache, UserCache}

  def value_parse(value, balance) do
    value =
      cond do
        is_nil(value) or is_nil(balance) ->
          nil

        Curie.check_typo(value, "all") ->
          balance

        balance > 0 and Curie.check_typo(value, "half") ->
          trunc(balance / 2)

        String.ends_with?(value, "%") and match?({_v, _r}, Integer.parse(value)) ->
          (balance / 100 * (Integer.parse(value) |> elem(0))) |> trunc()

        match?({_v, _r}, Integer.parse(value)) ->
          Integer.parse(value) |> elem(0)

        true ->
          nil
      end

    cond do
      value in 1..balance ->
        value

      true ->
        nil
    end
  end

  def get_balance(member) do
    case Postgrex.query!(Postgrex, "SELECT value FROM balance WHERE member=$1", [member]).rows do
      [] ->
        nil

      [[balance]] ->
        balance
    end
  end

  def change_balance(action, member, value) do
    [[balance]] =
      Postgrex.query!(Postgrex, "SELECT value FROM balance WHERE member=$1", [member]).rows

    new_balance =
      case action do
        :add ->
          balance + value

        :deduct ->
          balance - value

        :replace ->
          value
      end

    Postgrex.query!(Postgrex, "UPDATE balance SET value=$1 WHERE member=$2", [new_balance, member])
  end

  def validate_recipient(message) do
    case Curie.get_member(message, 2) do
      nil ->
        nil

      member ->
        if member.user.id |> get_balance(), do: member
    end
  end

  def whitelisted?(message) do
    case message.author.id |> get_balance() do
      nil ->
        with {:ok, guild} <- GuildCache.get(message.guild_id),
             {:ok, owner} <- UserCache.get(guild.owner_id) do
          "Whitelisting required, ask #{owner.username}."
          |> (&Curie.send(message.channel_id, content: &1)).()
        end

        false

      _value ->
        true
    end
  end

  def command({"balance", message, words}) when length(words) == 1 do
    if whitelisted?(message) do
      balance =
        message.author.id
        |> get_balance()
        |> (&"#{message.author.username} has #{&1}#{Curie.tempest()}.").()

      Curie.embed(message, balance, "lblue")
    end
  end

  def command({"balance", message, words}) when length(words) >= 2 do
    subcommand({Enum.at(words, 1), message, words})
  end

  def command({"gift", message, words}) when length(words) >= 3 do
    if whitelisted?(message) do
      case validate_recipient(message) do
        nil ->
          Curie.embed(message, "Invalid recipient.", "red")

        recipient ->
          author_balance = message.author.id |> get_balance()

          case value_parse(Enum.at(words, 1), author_balance) do
            nil ->
              Curie.embed(message, "Invalid amount.", "red")

            amount ->
              change_balance(:add, recipient.user.id, amount)
              change_balance(:deduct, message.author.id, amount)

              content =
                "#{message.author.username} gifted " <>
                  "#{amount}#{Curie.tempest()} to #{recipient.user.username}."

              Curie.embed(message, content, "lblue")
          end
      end
    end
  end

  def command({call, message, words}) do
    registered = ["balance", "gift"]
    with {:ok, match} <- Curie.check_typo(call, registered), do: command({match, message, words})
  end

  def subcommand({"curie", message, _words}) do
    balance =
      Nostrum.Cache.Me.get().id
      |> get_balance()
      |> (&"My balance is #{&1}#{Curie.tempest()}.").()

    Curie.embed(message, balance, "lblue")
  end

  def subcommand({call, message, words}) do
    with {:ok, match} <- Curie.check_typo(call, "curie"), do: subcommand({match, message, words})
  end

  def handler(message), do: if(Curie.command?(message), do: message |> Curie.parse() |> command())
end
