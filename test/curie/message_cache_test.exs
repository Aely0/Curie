defmodule MessageCacheTest do
  use ExUnit.Case, async: true

  alias Curie.MessageCache

  @guild_message %{
    __struct__: Nostrum.Struct.Message,
    activity: nil,
    application: nil,
    attachments: [],
    author: %Nostrum.Struct.User{
      avatar: "7c088084d173c3ab0d66fc2bd9e48dc8",
      bot: nil,
      discriminator: "2694",
      email: nil,
      id: 0,
      mfa_enabled: nil,
      username: "Andris",
      verified: nil
    },
    channel_id: 473_537_127_116_963_841,
    content: "Something",
    edited_timestamp: nil,
    embeds: [],
    guild_id: 473_537_126_680_494_111,
    heartbeat: %{ack: 642_000, send: 513_000},
    id: 486_592_759_839_588_353,
    mention_everyone: false,
    mention_roles: [],
    mentions: [],
    nonce: 486_592_775_559_577_600,
    pinned: false,
    reactions: nil,
    timestamp: "2018-09-04T17:45:54.402000+00:00",
    tts: false,
    type: 0,
    webhook_id: nil
  }

  @direct_message %{
    __struct__: Nostrum.Struct.Message,
    activity: nil,
    application: nil,
    attachments: [],
    author: %Nostrum.Struct.User{
      avatar: "7c088084d173c3ab0d66fc2bd9e48dc8",
      bot: nil,
      discriminator: "2694",
      email: nil,
      id: 0,
      mfa_enabled: nil,
      username: "Andris",
      verified: nil
    },
    channel_id: 484_381_611_979_178_026,
    content: "Something",
    edited_timestamp: nil,
    embeds: [],
    guild_id: nil,
    heartbeat: %{ack: 452_000, send: 306_000},
    id: 486_602_766_744_027_147,
    mention_everyone: false,
    mention_roles: [],
    mentions: [],
    nonce: 486_602_782_262_951_936,
    pinned: false,
    reactions: nil,
    timestamp: "2018-09-04T18:25:40.234000+00:00",
    tts: false,
    type: 0,
    webhook_id: nil
  }

  test "retrieve cached messages" do
    for message <- [
          @guild_message,
          %{@guild_message | content: "Else"},
          @direct_message,
          %{@direct_message | content: "Else"}
        ] do
      MessageCache.handler(message)
    end

    guild_message_delete_event = %{
      guild_id: @guild_message.guild_id,
      channel_id: @guild_message.channel_id,
      id: @guild_message.id
    }

    direct_message_delete_event = %{
      channel_id: @direct_message.channel_id,
      id: @direct_message.id
    }

    # Get messages
    {:ok, [%{id: message_id} | _]} = MessageCache.get(guild_message_delete_event)
    assert message_id == @guild_message.id

    {:ok, [%{id: message_id} | _]} = MessageCache.get(direct_message_delete_event)
    assert message_id == @direct_message.id

    {:ok, [message | _]} = MessageCache.get(@guild_message.id)
    assert message == @guild_message

    {:ok, [message | _]} = MessageCache.get(@direct_message.id)
    assert message == @direct_message

    assert MessageCache.get(%{guild_id: 1, channel_id: 2, id: 3}) == {:error, :not_found}
    assert MessageCache.get(%{channel_id: 2, id: 3}) == {:error, :not_found}
    assert MessageCache.get(0) == {:error, :not_found}

  end

  test "filter messages to ignore" do
    owner = Application.get_env(:curie, :owner)
    me = Nostrum.Api.get_current_user!().id
    random_id = 123_452_345_345_455

    for {user, ignore?} <- [{owner, true}, {me, true}, {random_id, false}] do
      assert MessageCache.ignore?(%{author: %{id: user}}) == ignore?
      assert MessageCache.ignore?(%{user: %{id: user}}) == ignore?
    end
  end
end
