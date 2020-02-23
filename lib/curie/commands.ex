defmodule Curie.Commands do
  alias Nostrum.Struct.Message

  @type command_call :: {String.t(), Message.t(), [String.t()]}
  @type words_to_check :: String.t() | [String.t()]

  @callback command(command_call) :: any

  @prefix Application.get_env(:curie, :prefix)

  defmacro __using__(_opts) do
    quote location: :keep do
      alias unquote(__MODULE__)

      @behaviour unquote(__MODULE__)
      @super unquote(__MODULE__)

      @owner %{author: %{id: Application.get_env(:curie, :owner)}}
      @tempest Application.get_env(:curie, :tempest)
      @prefix Application.get_env(:curie, :prefix)
    end
  end

  @spec command?(Message.t()) :: boolean
  def command?(%{content: @prefix <> _content}), do: true
  def command?(_not_a_command), do: false

  @spec parse(Message.t()) :: command_call
  def parse(%{content: content} = message) do
    [@prefix <> call | args] = String.split(content, ~r(\s))
    call = String.downcase(call)
    {call, message, args}
  end

  @spec check_typo(command_call, words_to_check, function) :: any
  def check_typo({call, message, args}, check, caller) do
    with match when match not in [call, nil] <- Curie.check_typo(call, check) do
      caller.({match, message, args})
    else
      _no_match -> :pass
    end
  end
end
