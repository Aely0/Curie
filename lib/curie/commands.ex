defmodule Curie.Commands do
  alias Nostrum.Struct.Message

  @callback command({String.t(), Message.t(), [String.t()]}) :: no_return()

  defmacro __using__(_opts) do
    quote do
      @behaviour Curie.Commands

      @owner %{author: %{id: Application.get_env(:curie, :owner)}}
      @tempest Application.get_env(:curie, :tempest)
      @prefix Application.get_env(:curie, :prefix)

      def command?(%{content: content} = message), do: String.starts_with?(content, @prefix)

      def parse(%{content: content} = message) do
        [@prefix <> call | args] = String.split(content)
        call = String.downcase(call)
        {call, message, args}
      end

      def check_typo({call, message, args}, check, caller) do
        with match when match != nil <- Curie.check_typo(call, check),
             do: if(call != match, do: caller.({match, message, args}))
      end

      def handler(message), do: if(command?(message), do: message |> parse() |> command())

      defoverridable handler: 1
    end
  end
end
