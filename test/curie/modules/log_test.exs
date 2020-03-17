defmodule LogTest do
  use ExUnit.Case, async: true

  alias Nostrum.Api

  alias Curie.Log
  alias Curie.MessageCache

  defp add_ids(map) do
    Map.merge(map, %{
      member_id: Application.get_env(:curie, :owner),
      guild_id: Application.get_env(:curie, :guild),
      logs_id: Application.get_env(:curie, :channels).logs,
      test1_id: Application.get_env(:curie, :channels).test1
    })
  end

  defp add_invitee_and_invites(map) do
    Map.merge(map, %{
      invitee: %{user: %{username: "Someone"}},
      invites: [
        %Nostrum.Struct.Invite{
          created_at: "2018-08-29T14:35:47.947000+00:00",
          inviter: %Nostrum.Struct.User{username: "Andris"},
          uses: 1
        },
        %Nostrum.Struct.Invite{
          created_at: "2018-08-29T14:36:16.968000+00:00",
          inviter: %Nostrum.Struct.User{username: "Andris"},
          uses: 0
        }
      ]
    })
  end

  defp add_deleted_message(map) do
    Map.merge(map, %{
      deleted_messages: %{
        base: %Nostrum.Struct.Message{
          attachments: [
            %Nostrum.Struct.Message.Attachment{filename: "1.txt"}
          ],
          author: %Nostrum.Struct.User{
            discriminator: "4848",
            username: "Curie"
          },
          channel_id: map.logs_id,
          content: "Something",
          embeds: [
            %Nostrum.Struct.Embed{
              author: nil,
              color: 6_570_405,
              description: "Embed",
              fields: nil,
              footer: nil,
              image: nil,
              provider: nil,
              thumbnail: nil,
              timestamp: nil,
              title: nil,
              type: "rich",
              url: nil,
              video: nil
            }
          ],
          guild_id: map.guild_id,
          id: 579_283_417_431_277_572
        }
      }
    })
  end

  defp add_deleted_message_variations(map) do
    Map.merge(map, %{
      deleted_messages: %{
        not_loggable: map.deleted_messages.base,
        direct: %{
          map.deleted_messages.base
          | id: 579_283_251_684_835_329,
            channel_id: 181_390_171_168_571_392,
            guild_id: nil
        },
        logged: %{
          map.deleted_messages.base
          | id: 579_283_247_691_989_003,
            channel_id: map.test1_id
        },
        logged_description:
          "#test1 Curie#4848: Something [\"1.txt\"] " <>
            "[%Nostrum.Struct.Embed{author: nil, color: 6570405, description: \"Embed\", " <>
            "fields: nil, footer: nil, image: nil, provider: nil, thumbnail: nil, " <>
            "timestamp: nil, title: nil, type: \"rich\", url: nil, video: nil}]"
      }
    })
  end

  defp add_messages_to_cache(%{deleted_messages: messages} = map) do
    for message <- [messages.not_loggable, messages.direct, messages.logged] do
      MessageCache.handler(message)
    end

    map
  end

  setup_all do
    Map.new()
    |> add_ids()
    |> add_invitee_and_invites()
    |> add_deleted_message()
    |> add_deleted_message_variations()
    |> add_messages_to_cache()
  end

  describe "Log.iso_to_unix/1" do
    test "parse iso extended timestamp" do
      assert Log.iso_to_unix("2018-08-29T14:18:34.199000+00:00") == 1_535_552_314
    end

    test "parse invalid timestamp" do
      assert Log.iso_to_unix("None") == nil
    end

    test "parse invalid type" do
      assert Log.iso_to_unix(nil) == nil
    end
  end

  describe "Log.join/2" do
    test "check for discord notification", %{invitee: invitee, invites: invites} do
      {:ok, %{embeds: [%{description: description}]} = message} = Log.join(invites, invitee)

      assert String.contains?(description, "Andris invited Someone to the guild. (2)")
      Api.delete_message(message)
    end
  end

  describe "Log.delete/1" do
    test "deleted message in #logs (ignore)", %{deleted_messages: %{not_loggable: message}} do
      assert Log.delete(message) == :ignore
    end

    test "delete message in DM (ignore)", %{deleted_messages: %{direct: message}} do
      assert Log.delete(message) == :ignore
    end

    test "delete message in #test1 (log)", %{deleted_messages: messages} do
      {:ok, %{embeds: [%{description: description}]} = log_message} = Log.delete(messages.logged)

      assert description == messages.logged_description
      Api.delete_message(log_message)
    end
  end

  describe "Log.leave/1" do
    test "member leave notification", %{invitee: %{user: %{username: name}} = member} do
      {:ok, %{embeds: [%{description: description}]} = log_message} = Log.leave(member)

      assert String.contains?(description, "#{name} left the guild.")
      Api.delete_message(log_message)
    end
  end
end
