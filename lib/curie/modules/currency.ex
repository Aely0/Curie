defmodule Curie.Currency do
  use Curie.Commands

  alias Nostrum.Cache.{GuildCache, UserCache}
  alias Curie.Data.Balance
  alias Curie.Data

  @check_typo %{command: ["balance", "gift"], subcommand: ["curie"]}

  def value_parse(value, balance) do
    cond do
      value == nil or balance == nil ->
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

  def whitelist_message(%{guild_id: guild_id} = message) do
    with {:ok, %{owner_id: owner_id} = _guild} <- GuildCache.get(guild_id),
         {:ok, %{username: name} = _owner} <- UserCache.get(owner_id) do
      "Whitelisting required, ask #{name}."
      |> (&Curie.embed(message, &1, "red")).()
    end
  end

  def validate_recipient(message) do
    Curie.get_member(message, 2)
    |> (&if(&1 != nil and whitelisted?(&1), do: &1)).()
  end

  def command({"balance", %{author: %{id: member, username: name}} = message, args})
      when args == [] do
    if whitelisted?(message) do
      member
      |> get_balance()
      |> (&"#{name} has #{&1}#{@tempest}.").()
      |> (&Curie.embed(message, &1, "lblue")).()
    else
      whitelist_message(message)
    end
  end

  def command({"balance", message, [call | _rest] = args}), do: subcommand({call, message, args})

  def command({"gift", %{author: %{id: author, username: gifter}} = message, [value | _] = args})
      when length(args) >= 2 do
    if whitelisted?(message) do
      case validate_recipient(message) do
        nil ->
          Curie.embed(message, "Invalid recipient.", "red")

        %{user: %{id: target, username: giftee}} ->
          case value_parse(value, get_balance(author)) do
            nil ->
              Curie.embed(message, "Invalid amount.", "red")

            amount ->
              change_balance(:deduct, author, amount)
              change_balance(:add, target, amount)

              "#{gifter} gifted #{amount}#{@tempest} to #{giftee}."
              |> (&Curie.embed(message, &1, "lblue")).()
          end
      end
    else
      whitelist_message(message)
    end
  end

  def command(call), do: check_typo(call, @check_typo.command, &command/1)

  def subcommand({"curie", message, _args}) do
    Nostrum.Cache.Me.get().id
    |> get_balance()
    |> (&"My balance is #{&1}#{@tempest}.").()
    |> (&Curie.embed(message, &1, "lblue")).()
  end

  def subcommand(call), do: check_typo(call, @check_typo.subcommand, &subcommand/1)
end
