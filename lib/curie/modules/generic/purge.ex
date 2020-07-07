defmodule Curie.Generic.Purge do
  import Nostrum.Snowflake, only: [is_snowflake: 1]

  alias Nostrum.Api
  alias Nostrum.Struct.{Channel, Message}

  @limit 100
  @snowflake_identifier ["s", "S"]
  @locators ["after", "before"]
  @curie_flag ["curie"]

  @spec parse_amount([String.t()]) :: pos_integer | nil
  defp parse_amount(options) do
    Enum.find_value(
      options,
      &case Integer.parse(&1) do
        {amount, _} when 0 < amount and amount < 100_000 -> amount + 1
        _invalid_value -> nil
      end
    )
  end

  @spec parse_locator([String.t()]) :: atom
  defp parse_locator(options) do
    Enum.find_value(
      options,
      List.first(@locators),
      &case &1 |> String.downcase() |> Curie.check_typo(@locators) do
        locator when is_binary(locator) -> String.to_atom(locator)
        _ -> nil
      end
    )
  end

  @spec parse_snowflake([String.t()]) :: non_neg_integer | nil
  defp parse_snowflake(options) do
    Enum.find_value(
      options,
      &if String.starts_with?(&1, @snowflake_identifier) do
        &1
        |> String.replace(@snowflake_identifier, "")
        |> Integer.parse()
        |> case do
          {snowflake, _} when is_snowflake(snowflake) -> snowflake
          _ -> nil
        end
      end
    )
  end

  @spec parse_curie_flag([String.t()]) :: String.t() | nil
  defp parse_curie_flag(options) do
    Enum.find_value(options, &(&1 |> String.downcase() |> Curie.check_typo(@curie_flag)))
  end

  @spec get_message_ids(Channel.id(), pos_integer, boolean, tuple) ::
          {:ok, [Message.id()]} | Api.error()
  defp get_message_ids(channel, amount, false, locator) do
    case Api.get_channel_messages(channel, amount, locator) do
      {:ok, messages} -> {:ok, Enum.map(messages, & &1.id)}
      {:error, _} = error -> error
    end
  end

  defp get_message_ids(channel, amount, true, locator) do
    with {:ok, curie_id} <- Curie.my_id(),
         {:ok, messages} <- Api.get_channel_messages(channel, amount, locator) do
      {:ok,
       Enum.reduce(messages, [], fn
         %{id: id, author: %{id: ^curie_id}}, acc -> [id | acc]
         _skip_message, acc -> acc
       end)}
    else
      {:error, _} = error -> error
    end
  end

  @spec delete_messages(Message.id(), Channel.id(), pos_integer, boolean, tuple) ::
          :ok | {:ok, Message.t()} | Api.error()
  defp delete_messages(call, channel, amount, curie, locator \\ {}) do
    with {:ok, messages} <- get_message_ids(channel, amount, curie, locator),
         messages = [call | messages] |> Enum.sort() |> Enum.dedup(),
         {:ok} <- Api.bulk_delete_messages(channel, messages) do
      :ok
    else
      {:error, reason} -> Curie.embed(channel, inspect(reason), "red")
    end
  end

  @spec clear(Message.t(), [String.t()]) :: :ok | {:ok, Message.t()} | Api.error() | :pass
  def clear(%{id: message, channel_id: channel}, options) do
    amount = parse_amount(options)
    locator = parse_locator(options)
    snowflake = parse_snowflake(options)
    curie = parse_curie_flag(options)

    case {!!amount, !!snowflake, !!curie} do
      {true, false, curie} ->
        delete_messages(message, channel, amount, curie)

      {_amount, true, curie} ->
        delete_messages(message, channel, amount || @limit, curie, {locator, snowflake})

      _invalid_call ->
        :pass
    end
  end
end
