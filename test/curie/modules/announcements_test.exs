defmodule AnnouncementsTest do
  use ExUnit.Case, async: true

  alias Nostrum.Api

  alias Curie.Data.Streams
  alias Curie.Data

  alias Curie.Announcements
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

  defp add_stream_presence(%{guild_id: guild_id, member_id: member_id} = map) do
    auth = [{"Client-ID", Application.get_env(:curie, :twitch)}]
    channel_url = "https://api.twitch.tv/helix/streams?first=1"
    {:ok, %{body: body}} = Curie.get(channel_url, auth)
    {:ok, %{"data" => [channel | _]}} = Poison.decode(body)

    Map.merge(map, %{
      stream_presence:
        {guild_id, %{},
         %{
           game: %{
             type: 1,
             url: "https://www.twitch.tv/" <> channel["user_name"],
             name: channel["title"],
           },
           user: %{id: member_id}
         }}
    })
  end

  defp add_messages_to_cache(%{deleted_messages: messages} = map) do
    for message <- [messages.not_loggable, messages.direct, messages.logged] do
      MessageCache.handler(message)
    end

    map
  end

  defp clear_stream_cooldown(member_id) do
    case Data.get(Streams, member_id) do
      %Streams{} = entry -> Data.delete(entry)
      _no_entry -> nil
    end
  end

  setup_all do
    Map.new()
    |> add_ids()
    |> add_invitee_and_invites()
    |> add_deleted_message()
    |> add_deleted_message_variations()
    |> add_messages_to_cache()
    |> add_stream_presence()
  end

  describe "Announcements.iso_to_unix/1" do
    test "parse iso extended timestamp" do
      assert Announcements.iso_to_unix("2018-08-29T14:18:34.199000+00:00") == 1_535_552_314
    end

    test "parse invalid timestamp" do
      assert Announcements.iso_to_unix("None") == nil
    end

    test "parse invalid type" do
      assert Announcements.iso_to_unix(nil) == nil
    end
  end

  describe "Announcements.join_log/2" do
    test "check for discord notification", %{invitee: invitee, invites: invites} do
      {:ok, %{embeds: [%{description: description}]} = message} =
        Announcements.join_log(invites, invitee)

      assert String.contains?(description, "Andris invited Someone to the guild. (2)")
      Api.delete_message(message)
    end
  end

  describe "Announcements.delete_log/1" do
    test "deleted message in #logs (ignore)", %{deleted_messages: %{not_loggable: message}} do
      assert Announcements.delete_log(message) == :ignore
    end

    test "delete message in DM (ignore)", %{deleted_messages: %{direct: message}} do
      assert Announcements.delete_log(message) == :ignore
    end

    test "delete message in #test1 (log)", %{deleted_messages: messages} do
      {:ok, %{embeds: [%{description: description}]} = log_message} =
        Announcements.delete_log(messages.logged)

      assert description == messages.logged_description
      Api.delete_message(log_message)
    end
  end

  describe "Announcements.leave_log/1" do
    test "member leave notification", %{invitee: %{user: %{username: name}} = member} do
      {:ok, %{embeds: [%{description: description}]} = log_message} =
        Announcements.leave_log(member)

      assert String.contains?(description, "#{name} left the guild.")
      Api.delete_message(log_message)
    end
  end

  describe "Stream announcement cooldowns" do
    test "check for non-existing cooldown", %{member_id: member_id} do
      clear_stream_cooldown(member_id)
      assert !Announcements.has_cooldown?(member_id)
    end

    test "set cooldown and check for it", %{member_id: member_id} do
      clear_stream_cooldown(member_id)
      Announcements.set_cooldown(member_id)
      assert Announcements.has_cooldown?(member_id)
    end

    test "set and check for expired cooldown", %{member_id: member_id} do
      clear_stream_cooldown(member_id)

      %Streams{member: member_id}
      |> Streams.changeset(%{time: Timex.to_unix(Timex.now()) - 30_000})
      |> Data.insert()

      assert !Announcements.has_cooldown?(member_id)
    end
  end

  describe "Announcements.stream/1" do
    test "check stream embed content",
         %{member_id: member_id, stream_presence: {_, _, %{game: game}} = presence} do
      clear_stream_cooldown(member_id)

      {:ok, %{embeds: [embed]} = message} = Announcements.stream(presence)

      # Embed title "#{member_name} started streaming!"
      assert String.contains?(embed.author.name, "started streaming!")

      # Clickable link leading to member's Twitch page
      assert embed.description == "[#{game.name}](#{game.url})"

      # Set cooldown on first occurance prevents announcement spam
      assert Announcements.stream(presence) == :pass

      Api.delete_message(message)
    end
  end
end
