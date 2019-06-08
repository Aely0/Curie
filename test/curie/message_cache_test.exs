defmodule MessageCacheTest do
  use ExUnit.Case, async: true
  alias Curie.MessageCache

  defp add_messages(map) do
    Map.merge(map, %{
      guild_message: %{
        __struct__: Nostrum.Struct.Message,
        author: %Nostrum.Struct.User{id: 0},
        channel_id: 473_537_127_116_963_841,
        content: "Something",
        guild_id: 473_537_126_680_494_111,
        id: 486_592_759_839_588_353
      },
      guild_message_edit: %{
        __struct__: Nostrum.Struct.Message,
        author: %Nostrum.Struct.User{id: 0},
        channel_id: 473_537_127_116_963_841,
        content: "Else",
        guild_id: 473_537_126_680_494_111,
        id: 486_592_759_839_588_353
      },
      direct_message: %{
        __struct__: Nostrum.Struct.Message,
        author: %Nostrum.Struct.User{id: 0},
        channel_id: 484_381_611_979_178_026,
        content: "Something",
        guild_id: nil,
        id: 486_602_766_744_027_147
      }
    })
  end

  defp add_delete_events(%{guild_message: guild_message, direct_message: direct_message} = map) do
    Map.merge(map, %{
      guild_message_delete_event: %{
        guild_id: guild_message.guild_id,
        channel_id: guild_message.channel_id,
        id: guild_message.id
      },
      direct_message_delete_event: %{
        channel_id: direct_message.channel_id,
        id: direct_message.id
      }
    })
  end

  defp add_false_retrieval_details(map) do
    Map.merge(map, %{
      false_details: [
        %{guild_id: 1, channel_id: 2, id: 3},
        %{channel_id: 2, id: 3},
        0
      ]
    })
  end

  defp add_ignore_set(map) do
    Map.merge(map, %{
      ignore_set: [
        {Application.get_env(:curie, :owner), true},
        {elem(Curie.my_id(), 1), true},
        {123_452_345_345_455, false}
      ]
    })
  end

  defp add_messages_to_cache(messages) do
    for {_key, message} <- messages do
      MessageCache.handler(message)
    end

    messages
  end

  setup_all do
    Map.new()
    |> add_messages()
    |> add_messages_to_cache()
    |> add_delete_events()
    |> add_false_retrieval_details()
    |> add_ignore_set()
  end

  describe "MessageCache.get/1|/2" do
    test "get guild message with delete payload", context do
      {:ok, [guild_message, guild_message_edit]} =
        MessageCache.get(context.guild_message_delete_event)

      assert guild_message.id == context.guild_message.id and
               guild_message_edit.id == context.guild_message.id
    end

    test "get direct message with delete payload", context do
      {:ok, [direct_message]} = MessageCache.get(context.direct_message_delete_event)
      assert direct_message.id == context.direct_message.id
    end

    test "get guild message by id", %{guild_message: %{id: message_id}} do
      {:ok, [%{id: cached_message_id}, %{id: cached_message_edit_id}]} =
        MessageCache.get(message_id)

      assert cached_message_id == message_id and cached_message_edit_id == message_id
    end

    test "get direct message by id", %{direct_message: %{id: message_id}} do
      {:ok, [%{id: cached_message_id}]} = MessageCache.get(message_id)
      assert cached_message_id == message_id
    end

    test "fetch with false payloads and ids", %{false_details: false_details} do
      for parameters <- false_details do
        assert MessageCache.get(parameters) == {:error, :not_found}
      end
    end
  end

  describe "MessageCache.ignore?/1" do
    test "check message ignoring", %{ignore_set: ignore_set} do
      for {id, ignore?} = set <- ignore_set do
        assert MessageCache.ignore?(%{author: %{id: id}}) == ignore?, inspect(set)
      end
    end
  end
end
