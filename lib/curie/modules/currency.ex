defmodule Curie.Currency do
  use Curie.Commands

  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Struct.User
  alias Curie.Data.Balance
  alias Curie.Data
  alias Curie.Storage

  @check_typo ~w/balance gift/

  @spec value_parse(User.id(), String.t()) :: pos_integer() | nil
  def value_parse(member_id, value) when is_integer(member_id) and is_binary(value) do
    value_parse(value, get_balance(member_id))
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

  @spec get_balance(User.id()) :: Balance.value() | nil
  def get_balance(member_id) do
    with %{value: value} <- Data.get(Balance, member_id) do
      value
    end
  end

  @spec change_balance(:add | :deduct | :replace, User.id(), integer()) :: no_return()
  def change_balance(action, member_id, value) do
    balance = Data.get(Balance, member_id)

    case action do
      :add -> balance.value + value
      :deduct -> balance.value - value
      :replace -> value
    end
    |> (&Balance.changeset(balance, %{value: &1})).()
    |> Data.update()
  end

  @spec validate_recipient(map()) :: Member.t() | nil
  def validate_recipient(message) do
    case Curie.get_member(message, 2) do
      {:ok, member} ->
        if Storage.whitelisted?(member) do
          member
        end

      {:error, _reason} ->
        nil
    end
  end

  @impl Curie.Commands
  def command({"balance", %{author: %{id: member_id}} = message, []}) do
    if Storage.whitelisted?(message) do
      member_id
      |> get_balance()
      |> (&"#{Curie.get_display_name(message)} has #{&1}#{@tempest}.").()
      |> (&Curie.embed(message, &1, "lblue")).()
    else
      Storage.whitelist_message(message)
    end
  end

  @impl Curie.Commands
  def command({"balance", message, [curie | _rest]}) do
    if Curie.check_typo(curie, "curie") do
      Curie.my_id()
      |> elem(1)
      |> get_balance()
      |> (&"My balance is #{&1}#{@tempest}.").()
      |> (&Curie.embed(message, &1, "lblue")).()
    else
      command({"balance", message, []})
    end
  end

  @impl Curie.Commands
  def command({"gift", %{author: %{id: gifter}} = message, [value | _]}) do
    if Storage.whitelisted?(message) do
      case validate_recipient(message) do
        nil ->
          Curie.embed(message, "Invalid recipient.", "red")

        %{user: %{id: giftee}} when giftee == gifter ->
          Curie.embed(message, "Really...?", "red")

        %{nick: nick, user: %{id: giftee, username: username}} ->
          case value_parse(value, get_balance(gifter)) do
            nil ->
              Curie.embed(message, "Invalid amount.", "red")

            amount ->
              change_balance(:deduct, gifter, amount)
              change_balance(:add, giftee, amount)

              gifter = Curie.get_display_name(message)
              giftee = nick || username

              "#{gifter} gifted #{amount}#{@tempest} to #{giftee}."
              |> (&Curie.embed(message, &1, "lblue")).()
          end
      end
    else
      Storage.whitelist_message(message)
    end
  end

  @impl Curie.Commands
  def command(call) do
    check_typo(call, @check_typo, &command/1)
  end
end
