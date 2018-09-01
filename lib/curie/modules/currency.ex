defmodule Curie.Currency do
  use Curie.Commands

  alias Nostrum.Cache.{GuildCache, UserCache}
  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Struct.User
  alias Curie.Data.Balance
  alias Curie.Data

  @check_typo %{command: ~w/balance gift/, subcommand: ~w/curie/}

  @spec value_parse(User.id(), String.t()) :: pos_integer() | nil
  def value_parse(member, value) when is_integer(member) and is_binary(value) do
    value_parse(value, get_balance(member))
  end

  @spec value_parse(String.t(), integer() | nil) :: pos_integer() | nil
  def value_parse(_value, 0), do: nil

  def value_parse(_value, nil), do: nil

  def value_parse(value, balance) when is_binary(value) and is_integer(balance) do
    cond do
      Curie.check_typo(value, "all") -> balance
      Curie.check_typo(value, "half") && balance > 0 -> trunc(balance / 2)
      value =~ ~r/^\d+%/ -> (balance / 100 * (value |> Integer.parse() |> elem(0))) |> trunc()
      value =~ ~r/^\d+/ -> Integer.parse(value) |> elem(0)
      true -> nil
    end
    |> (&if(&1 != nil and &1 in 1..balance, do: &1)).()
  end

  @spec get_balance(User.id()) :: integer() | nil
  def get_balance(member) do
    with %{value: value} <- Data.get(Balance, member) do
      value
    end
  end

  @spec change_balance(:add | :deduct | :replace, User.id(), integer()) :: no_return()
  def change_balance(action, member, value) do
    member = Data.get(Balance, member)

    case action do
      :add -> member.value + value
      :deduct -> member.value - value
      :replace -> value
    end
    |> (&Balance.changeset(member, %{value: &1})).()
    |> Data.update()
  end

  @spec whitelisted?(%{author: %{id: User.id()}}) :: boolean()
  def whitelisted?(%{author: %{id: id}} = _message) do
    id |> get_balance() |> is_integer()
  end

  @spec whitelisted?(%{user: %{id: User.id()}}) :: boolean()
  def whitelisted?(%{user: %{id: id}} = _member) do
    id |> get_balance() |> is_integer()
  end

  @spec whitelist_message(map()) :: no_return()
  def whitelist_message(%{guild_id: guild_id} = message) do
    with {:ok, %{owner_id: owner_id} = _guild} <- GuildCache.get(guild_id),
         {:ok, %{username: name} = _owner} <- UserCache.get(owner_id) do
      "Whitelisting required, ask #{name}."
      |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @spec validate_recipient(map()) :: Member.t() | nil
  def validate_recipient(message) do
    message
    |> Curie.get_member(2)
    |> (&if(&1 != nil and whitelisted?(&1), do: &1)).()
  end

  @impl true
  def command({"balance", %{author: %{id: member, username: name}} = message, []}) do
    if whitelisted?(message) do
      member
      |> get_balance()
      |> (&"#{name} has #{&1}#{@tempest}.").()
      |> (&Curie.embed(message, &1, "lblue")).()
    else
      whitelist_message(message)
    end
  end

  @impl true
  def command({"balance", message, [call | _rest] = args}) do
    subcommand({call, message, args})
  end

  @impl true
  def command({"gift", %{author: %{id: author, username: gifter}} = message, [value | _]}) do
    if whitelisted?(message) do
      case validate_recipient(message) do
        nil ->
          Curie.embed(message, "Invalid recipient.", "red")

        %{user: %{id: target}} when target == author ->
          Curie.embed(message, "Really...?", "red")

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

  @impl true
  def command(call) do
    check_typo(call, @check_typo.command, &command/1)
  end

  @impl true
  def subcommand({"curie", message, _args}) do
    Nostrum.Cache.Me.get().id
    |> get_balance()
    |> (&"My balance is #{&1}#{@tempest}.").()
    |> (&Curie.embed(message, &1, "lblue")).()
  end

  @impl true
  def subcommand(call) do
    check_typo(call, @check_typo.subcommand, &subcommand/1)
  end
end
