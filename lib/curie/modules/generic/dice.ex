defmodule Curie.Generic.Dice do
  @type dice_count :: pos_integer()
  @type side_count :: pos_integer()
  @type display_mode :: String.t()
  @type dice_type :: String.t()
  @type parsed_dice_count :: {:ok, dice_count()} | {:error, atom()}
  @type parsed_side_count :: {:ok, side_count()} | {:error, atom()}
  @type parsed_display_mode :: {:ok, display_mode()} | {:error, atom()}
  @type successful_component_parse ::
          {:ok, {dice_count(), side_count(), display_mode(), dice_type()}}
  @type unsuccessful_component_parse ::
          {parsed_dice_count(), parsed_side_count(), parsed_display_mode()}
  @type component_parsing_result ::
          successful_component_parse()
          | unsuccessful_component_parse()
          | (early_failure :: {:error, atom()})

  @dice_regex_pattern ~r/^(\d*)[dD](\d*)(\w?)$/
  @dice_count_limit 1000
  @dice_side_limit 1_000_000

  @spec parse_error({:error, atom()} | unsuccessful_component_parse()) :: String.t()
  defp parse_error({:error, reason}) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp parse_error({_, _, _} = multiple) do
    multiple
    |> Tuple.to_list()
    |> Enum.filter(&match?({:error, _reason}, &1))
    |> Enum.map(&parse_error/1)
    |> Enum.join("\n")
  end

  @spec parse_count(String.t()) :: parsed_dice_count()
  defp parse_count(""), do: {:ok, 1}

  defp parse_count(count) do
    case Integer.parse(count) do
      {count, _rest} when count in 1..@dice_count_limit -> {:ok, count}
      {_count, _rest} -> {:error, :out_of_range_dice_count}
      :error -> {:error, :invalid_dice_count}
    end
  end

  @spec parse_sides(String.t()) :: parsed_side_count()
  defp parse_sides(sides) do
    case Integer.parse(sides) do
      {sides, _rest} when sides in 1..@dice_side_limit -> {:ok, sides}
      {_sides, _rest} -> {:error, :out_of_range_side_count}
      :error -> {:error, :invalid_side_count}
    end
  end

  @spec parse_mode(String.t()) :: parsed_display_mode()
  defp parse_mode(mode) when mode in ["", "r", "R"], do: {:ok, "R"}
  defp parse_mode(mode) when mode in ["e", "E"], do: {:ok, "E"}
  defp parse_mode(_invalid), do: {:error, :invalid_display_mode}

  @spec parse_type(nil | [String.t()]) :: component_parsing_result()
  defp parse_type(nil), do: {:error, :invalid_dice_type}

  defp parse_type([count, sides, mode]) do
    case {parse_count(count), parse_sides(sides), parse_mode(mode)} do
      {{:ok, 1}, {:ok, sides}, {:ok, mode}} ->
        {:ok, {1, sides, mode, "D#{sides}"}}

      {{:ok, count}, {:ok, sides}, {:ok, mode}} ->
        {:ok, {count, sides, mode, "#{count}D#{sides}"}}

      error ->
        error
    end
  end

  @spec parse_dice(String.t()) :: component_parsing_result()
  defp parse_dice(dice) do
    @dice_regex_pattern
    |> Regex.run(dice, capture: :all_but_first)
    |> parse_type()
  end

  @spec roll(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def roll(dice) do
    case parse_dice(dice) do
      {:ok, {count, sides, "R", type}} ->
        dice = Enum.map(1..count, fn _die -> Enum.random(1..sides) end)
        {:ok, "#{type}: **#{Enum.sum(dice)}**"}

      {:ok, {count, sides, "E", type}} when count > 200 ->
        dice =
          1..count
          |> Enum.map(fn _die -> Enum.random(1..sides) end)
          |> Enum.split(200)
          |> elem(0)

        {:ok, "#{type}: [#{Enum.join(dice, ", ")}, ...] → **#{Enum.sum(dice)}**"}

      {:ok, {count, sides, "E", type}} ->
        dice = Enum.map(1..count, fn _die -> Enum.random(1..sides) end)
        {:ok, "#{type}: [#{Enum.join(dice, ", ")}] → **#{Enum.sum(dice)}**"}

      error ->
        {:error, parse_error(error)}
    end
  end
end
