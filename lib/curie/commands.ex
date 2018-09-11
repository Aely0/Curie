defmodule Curie.Commands do
  @type command_call :: {String.t(), map(), [String.t()]}
  @callback command(command_call) :: no_return()
  @callback subcommand(command_call) :: no_return()
  @optional_callbacks subcommand: 1

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      @owner %{author: %{id: Application.get_env(:curie, :owner)}}
      @tempest Application.get_env(:curie, :tempest)
      @prefix Application.get_env(:curie, :prefix)

      @spec command?(%{content: String.t()}) :: boolean()
      def command?(%{content: content}) do
        String.starts_with?(content, @prefix)
      end

      @spec parse(map()) :: unquote(__MODULE__).command_call()
      def parse(%{content: content} = message) do
        [@prefix <> call | args] = String.split(content)
        call = String.downcase(call)
        {call, message, args}
      end

      @spec check_typo(
              unquote(__MODULE__).command_call(),
              String.t() | [String.t()],
              function()
            ) :: no_return()
      def check_typo({call, message, args}, check, caller) do
        with match when match not in [call, nil] <- Curie.check_typo(call, check) do
          caller.({match, message, args})
        end
      end

      @spec handler(map()) :: no_return()
      def handler(message) do
        if command?(message) do
          message |> parse() |> command()
        end
      end

      defoverridable handler: 1
    end
  end
end
