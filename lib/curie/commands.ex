defmodule Curie.Commands do
  alias Nostrum.Struct.Message

  @type command_call :: {String.t(), Message.t(), [String.t()]}
  @type words_to_check :: String.t() | [String.t()]

  @callback command(command_call) :: any
  @callback subcommand(command_call) :: any
  @optional_callbacks command: 1, subcommand: 1

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
      @super unquote(__MODULE__)

      @owner %{author: %{id: Application.get_env(:curie, :owner)}}
      @tempest Application.get_env(:curie, :tempest)
      @prefix Application.get_env(:curie, :prefix)

      @spec command?(Message.t()) :: boolean
      def command?(%{content: content}) do
        String.starts_with?(content, @prefix)
      end

      @spec parse(Message.t()) :: @super.command_call
      def parse(%{content: content} = message) do
        [@prefix <> call | args] = String.split(content)
        call = String.downcase(call)
        {call, message, args}
      end

      @spec check_typo(@super.command_call, @super.words_to_check, function) :: any
      def check_typo({call, message, args}, check, caller) do
        with match when match not in [call, nil] <- Curie.check_typo(call, check) do
          caller.({match, message, args})
        else
          _no_match -> :pass
        end
      end

      @spec command(@super.command_call) :: any
      def command(_command_call), do: :pass

      @spec subcommand(@super.command_call) :: any
      def subcommand(_command_call), do: :pass

      @spec handler(Message.t()) :: any
      def handler(message) do
        if command?(message),
          do: message |> parse() |> command(),
          else: :pass
      end

      defoverridable command: 1, subcommand: 1, handler: 1
    end
  end
end
