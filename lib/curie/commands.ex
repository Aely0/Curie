defmodule Curie.Commands do
  @type command_call :: {String.t(), Nostrum.Struct.Message.t(), [String.t()]}

  @callback command(command_call) :: term
  @callback subcommand(command_call) :: term
  @optional_callbacks subcommand: 1

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      @owner %{author: %{id: Application.get_env(:curie, :owner)}}
      @tempest Application.get_env(:curie, :tempest)
      @prefix Application.get_env(:curie, :prefix)

      @spec command?(%{content: Nostrum.Struct.Message.content()}) :: boolean
      def command?(%{content: content} = _message), do: String.starts_with?(content, @prefix)

      @spec parse(Nostrum.Struct.Message.t()) :: unquote(__MODULE__).command_call
      def parse(%{content: content} = message) do
        [@prefix <> call | args] = String.split(content)
        call = String.downcase(call)
        {call, message, args}
      end

      @spec check_typo(
              unquote(__MODULE__).command_call,
              String.t() | [String.t()],
              function
            ) :: term
      def check_typo({call, message, args}, check, caller) do
        with match when match != nil <- Curie.check_typo(call, check),
             do: if(call != match, do: caller.({match, message, args}))
      end

      @spec handler(Nostrum.Struct.Message.t()) :: term
      def handler(message), do: if(command?(message), do: message |> parse() |> command())

      defoverridable handler: 1
    end
  end
end
