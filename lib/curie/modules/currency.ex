defmodule Curie.Currency do
  alias Nostrum.Cache.{GuildCache, UserCache}
  alias Curie.Data.Balance
  alias Curie.Data

  def value_parse(value, balance) do
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
    |> (&if(&1 in 1..balance, do: &1)).()
  end

  def get_balance(member), do: with(%{value: value} <- Data.get(Balance, member), do: value)

  def change_balance(action, member, value) do
    member = Data.get(Balance, member)

    case action do
      :add ->
        member.value + value

      :deduct ->
        member.value - value

      :replace ->
        value
    end
    |> (&Balance.changeset(member, %{value: &1})).()
    |> Data.update()
  end

  def whitelisted?(%{author: %{id: id}} = _message), do: id |> get_balance() |> is_integer()

  def whitelisted?(%{user: %{id: id}} = _member), do: id |> get_balance() |> is_integer()

  def whitelist_message(message) do
    with {:ok, guild} <- GuildCache.get(message.guild_id),
         {:ok, owner} <- UserCache.get(guild.owner_id) do
      "Whitelisting required, ask #{owner.username}."
      |> (&Curie.embed(message, &1, "red")).()
    end
  end

  def validate_recipient(message) do
    Curie.get_member(message, 2)
    |> (&if(!is_nil(&1) and whitelisted?(&1), do: &1)).()
  end

  def command({"balance", message, words}) when length(words) == 1 do
    if whitelisted?(message) do
      message.author.id
      |> get_balance()
      |> (&"#{message.author.username} has #{&1}#{Curie.tempest()}.").()
      |> (&Curie.embed(message, &1, "lblue")).()
    else
      whitelist_message(message)
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
          case value_parse(Enum.at(words, 1), get_balance(message.author.id)) do
            nil ->
              Curie.embed(message, "Invalid amount.", "red")

            amount ->
              change_balance(:add, recipient.user.id, amount)
              change_balance(:deduct, message.author.id, amount)

              ("#{message.author.username} gifted " <>
                 "#{amount}#{Curie.tempest()} to #{recipient.user.username}.")
              |> (&Curie.embed(message, &1, "lblue")).()
          end
      end
    else
      whitelist_message(message)
    end
  end

  def command({call, message, words}) do
    with {:ok, match} <- Curie.check_typo(call, ["balance", "gift"]),
         do: command({match, message, words})
  end

  def subcommand({"curie", message, _words}) do
    Nostrum.Cache.Me.get().id
    |> get_balance()
    |> (&"My balance is #{&1}#{Curie.tempest()}.").()
    |> (&Curie.embed(message, &1, "lblue")).()
  end

  def subcommand({call, message, words}) do
    with {:ok, match} <- Curie.check_typo(call, "curie"), do: subcommand({match, message, words})
  end

  def handler(message), do: if(Curie.command?(message), do: message |> Curie.parse() |> command())
end
