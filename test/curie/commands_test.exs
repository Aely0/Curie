defmodule CommandsTest do
  use ExUnit.Case, async: true

  # Defining test module as a command module
  use Curie.Commands

  # Implementing callbacks and optional attributes
  @check_typos ~w/call args message/
  def command({"call", _message, _args} = {call, _, _}), do: call
  def command({"args", _message, args}), do: args
  def command({"message", message, _args}), do: message
  def command(call), do: check_typo(call, @check_typos, &command/1)

  # The testing itself
  defp test_scenarios do
    [
      {%{content: @prefix <> "call"}, "call"},
      {%{content: @prefix <> "CALL"}, "call"},
      {%{content: @prefix <> "valls"}, "call"},
      {%{content: @prefix <> "something"}, :pass},
      {%{content: Enum.random(~w/! ? . - ~/ -- [@prefix]) <> "call"}, :pass},
      {%{content: @prefix <> "args list of args"}, ~w/list of args/},
      {%{content: @prefix <> "args something"}, ~w/something/},
      {%{content: @prefix <> "args"}, []},
      {%{content: @prefix <> "message", a: 1, b: 2},
       %{content: @prefix <> "message", a: 1, b: 2}},
      {%{content: @prefix, a: 1, c: 3}, :pass},
      {%{content: "", d: 4}, :pass}
    ]
  end

  test "comparing parsed command calls with expected results" do
    for {message, desired_result} <- test_scenarios() do
      handler_result = handler(message)
      assert handler_result == desired_result
    end
  end
end
