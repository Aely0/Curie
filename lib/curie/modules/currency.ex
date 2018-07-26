defmodule Curie.Currency do
  use Curie.Commands

  alias Nostrum.Cache.{GuildCache, UserCache}
  alias Nostrum.Struct.{Message, User}
  alias Nostrum.Struct.Guild.Member
  alias Curie.Data.Balance
  alias Curie.Data

  @check_typo %{command: ["balance", "gift"], subcommand: ["curie"]}

  @spec value_parse(String.t(), non_neg_integer | nil) :: pos_integer | nil
  def value_parse(value, balance) do
    cond do
      balance == nil ->
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

  @spec get_balance(User.id()) :: integer | nil
  def get_balance(member), do: with(%{value: value} <- Data.get(Balance, member), do: value)

  @spec change_balance(:add | :deduct | :replace, User.id(), integer) :: no_return
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

  @spec whitelisted?(%{author: %{id: User.id()}}) :: boolean
  def whitelisted?(%{author: %{id: id}} = _message), do: id |> get_balance() |> is_integer()

  @spec whitelisted?(%{user: %{id: User.id()}}) :: boolean
  def whitelisted?(%{user: %{id: id}} = _member), do: id |> get_balance() |> is_integer()

  @spec whitelist_message(Message.t()) :: Message.t() | no_return
  def whitelist_message(%{guild_id: guild_id} = message) do
    with {:ok, %{owner_id: owner_id} = _guild} <- GuildCache.get(guild_id),
         {:ok, %{username: name} = _owner} <- UserCache.get(owner_id) do
      "Whitelisting required, ask #{name}."
      |> (&Curie.embed(message, &1, "red")).()
    end
  end

  @spec validate_recipient(Message.t()) :: Member.t() | nil
  def validate_recipient(message) do
    Curie.get_member(message, 2)
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
  def command({"balance", message, [call | _rest] = args}), do: subcommand({call, message, args})

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
  def command(call), do: check_typo(call, @check_typo.command, &command/1)

  @impl true
  def subcommand({"curie", message, _args}) do
    Nostrum.Cache.Me.get().id
    |> get_balance()
    |> (&"My balance is #{&1}#{@tempest}.").()
    |> (&Curie.embed(message, &1, "lblue")).()
  end

  @impl true
  def subcommand(call), do: check_typo(call, @check_typo.subcommand, &subcommand/1)
end
