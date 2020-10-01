defmodule Curie.Currency do
  @moduledoc """
  Guild game currency system.
  """

  use Curie.Commands

  import Nostrum.Snowflake, only: [is_snowflake: 1]

  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Struct.{Message, User}

  alias Curie.Data
  alias Curie.Data.Balance
  alias Curie.Storage

  @check_typo ~w/balance gift/

  @spec parse(String.t(), integer | nil) :: pos_integer | nil
  defp parse(value, balance) when is_binary(value) and is_integer(balance) do
    cond do
      Curie.check_typo(value, "all") -> balance
      Curie.check_typo(value, "half") && balance > 0 -> trunc(balance / 2)
      value =~ ~r/^\d+%/ -> (balance / 100 * (value |> Integer.parse() |> elem(0))) |> trunc()
      value =~ ~r/^\d+/ -> Integer.parse(value) |> elem(0)
      true -> nil
    end
    |> (&if(&1 > 0 and &1 <= balance, do: &1)).()
  end

  @spec value_parse(User.id(), String.t()) :: pos_integer | nil
  def value_parse(user_id, value) when is_snowflake(user_id) and is_binary(value) do
    case get_balance(user_id) do
      {:ok, balance} -> parse(value, balance)
      {:error, _error} -> nil
    end
  end

  @spec get_balance(User.id() | Message.t()) ::
          {:ok, Balance.value()} | {:error, :no_existing_balance}
  def get_balance(user_id) when is_snowflake(user_id) do
    case Data.get(Balance, user_id) do
      %Balance{value: value} -> {:ok, value}
      nil -> {:error, :no_existing_balance}
    end
  end

  def get_balance(%Message{author: %User{id: user_id}}), do: get_balance(user_id)

  @spec change_balance(:add | :deduct | :replace, User.id(), integer) :: :ok
  def change_balance(action, user_id, value) do
    balance = Data.get(Balance, user_id)

    case action do
      :add -> balance.value + value
      :deduct -> balance.value - value
      :replace -> value
    end
    |> (&Balance.changeset(balance, %{value: &1})).()
    |> Data.update()

    :ok
  end

  @spec validate_recipient(Message.t()) :: Member.t() | nil
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
  def command({"balance", %{author: %{id: user_id}} = message, []}) do
    if Storage.whitelisted?(message) do
      case get_balance(user_id) do
        {:ok, balance} ->
          response = "#{Curie.get_display_name(message)} has #{balance}#{@tempest}."
          Curie.embed(message, response, "lblue")

        {:error, _error} ->
          Curie.embed(message, "No balance seems to exist?", "red")
      end
    else
      Storage.whitelist_message(message)
    end
  end

  @impl Curie.Commands
  def command({"balance", %{mentions: mentions} = message, [curie | _rest]}) do
    {:ok, curie_id} = Curie.my_id()
    curie_mentioned = fn %{id: user_id} -> user_id == curie_id end

    if Enum.any?(mentions, curie_mentioned) or Curie.check_typo(curie, "curie") do
      {:ok, balance} = get_balance(curie_id)
      Curie.embed(message, "My balance is #{balance}#{@tempest}", "lblue")
    else
      command({"balance", message, []})
    end
  end

  @impl Curie.Commands
  def command({"gift", %{author: %{id: gifter}} = message, [value | _]}) do
    if Storage.whitelisted?(message) do
      case validate_recipient(message) do
        nil ->
          Curie.embed(message, "Invalid recipient", "red")

        %{user: %{id: giftee}} when giftee == gifter ->
          Curie.embed(message, "Really...?", "red")

        %{nick: nick, user: %{id: giftee, username: username}} ->
          {:ok, balance} = get_balance(gifter)

          case value_parse(value, balance) do
            nil ->
              Curie.embed(message, "Invalid amount", "red")

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
    Commands.check_typo(call, @check_typo, &command/1)
  end
end
