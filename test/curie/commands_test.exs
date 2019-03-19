defmodule CommandsTest do
  use ExUnit.Case, async: true
  use Curie.Commands

  @check_typos ~w/call args message/

  def command({"call", _message, _args} = {call, _, _}), do: call
  def command({"args", _message, args}), do: args
  def command({"message", message, _args}), do: message
  def command(call), do: check_typo(call, @check_typos, &command/1)

  test "command call" do
    situations = [
      {%{content: @prefix <> "call"}, "call"},
      {%{content: @prefix <> "CALL"}, "call"},
      {%{content: @prefix <> "valls"}, "call"},
      {%{content: @prefix <> "something"}, nil},
      {%{content: "~call"}, nil},
      {%{content: @prefix <> "args list of args"}, ~w/list of args/},
      {%{content: @prefix <> "args something"}, ~w/something/},
      {%{content: @prefix <> "args"}, []},
      {%{content: @prefix <> "message", a: 1, b: 2},
       %{content: @prefix <> "message", a: 1, b: 2}},
      {%{content: @prefix, a: 1, c: 3}, nil},
      {%{content: "", d: 4}, nil}
    ]

    for {message, desired_result} <- situations do
      handler_result = handler(message)
      assert handler_result == desired_result
    end
  end
end
