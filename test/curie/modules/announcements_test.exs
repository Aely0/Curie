defmodule AnnouncementsTest do
  use ExUnit.Case, async: true

  alias Nostrum.Struct.Embed
  alias Nostrum.Api

  alias Curie.Data.Streams
  alias Curie.Data

  @andris 90_575_330_862_972_928
  @guild 473_537_126_680_494_111

  @invitee %{user: %{username: "Someone"}}
  @mock_invites [
    %Nostrum.Struct.Invite{
      channel: %Nostrum.Struct.Channel{
        application_id: nil,
        bitrate: nil,
        guild_id: nil,
        icon: nil,
        id: 473_537_127_116_963_841,
        last_message_id: nil,
        last_pin_timestamp: nil,
        name: "general",
        nsfw: nil,
        owner_id: nil,
        parent_id: nil,
        permission_overwrites: nil,
        position: nil,
        recipients: nil,
        topic: nil,
        type: 0,
        user_limit: nil
      },
      code: "RBNrVp",
      created_at: "2018-08-29T14:35:47.947000+00:00",
      guild: %Nostrum.Struct.Guild{
        afk_channel_id: nil,
        afk_timeout: nil,
        application_id: nil,
        channels: nil,
        default_message_notifications: nil,
        embed_channel_id: nil,
        embed_enabled: nil,
        emojis: nil,
        explicit_content_filter: nil,
        features: [],
        icon: "4365a9295ac51200f0a2ae4048dff277",
        id: 473_537_126_680_494_111,
        joined_at: nil,
        large: nil,
        member_count: nil,
        members: nil,
        mfa_level: nil,
        name: "Curie Dev",
        owner_id: nil,
        region: nil,
        roles: nil,
        splash: nil,
        system_channel_id: nil,
        unavailable: nil,
        verification_level: 0,
        voice_states: nil,
        widget_channel_id: nil,
        widget_enabled: nil
      },
      inviter: %Nostrum.Struct.User{
        avatar: "7c088084d173c3ab0d66fc2bd9e48dc8",
        bot: nil,
        discriminator: "2694",
        email: nil,
        id: 90_575_330_862_972_928,
        mfa_enabled: nil,
        username: "Andris",
        verified: nil
      },
      max_age: 86400,
      max_uses: 0,
      revoked: nil,
      temporary: false,
      uses: 1
    },
    %Nostrum.Struct.Invite{
      channel: %Nostrum.Struct.Channel{
        application_id: nil,
        bitrate: nil,
        guild_id: nil,
        icon: nil,
        id: 473_537_127_116_963_841,
        last_message_id: nil,
        last_pin_timestamp: nil,
        name: "general",
        nsfw: nil,
        owner_id: nil,
        parent_id: nil,
        permission_overwrites: nil,
        position: nil,
        recipients: nil,
        topic: nil,
        type: 0,
        user_limit: nil
      },
      code: "UxYH2",
      created_at: "2018-08-29T14:36:16.968000+00:00",
      guild: %Nostrum.Struct.Guild{
        afk_channel_id: nil,
        afk_timeout: nil,
        application_id: nil,
        channels: nil,
        default_message_notifications: nil,
        embed_channel_id: nil,
        embed_enabled: nil,
        emojis: nil,
        explicit_content_filter: nil,
        features: [],
        icon: "4365a9295ac51200f0a2ae4048dff277",
        id: 473_537_126_680_494_111,
        joined_at: nil,
        large: nil,
        member_count: nil,
        members: nil,
        mfa_level: nil,
        name: "Curie Dev",
        owner_id: nil,
        region: nil,
        roles: nil,
        splash: nil,
        system_channel_id: nil,
        unavailable: nil,
        verification_level: 0,
        voice_states: nil,
        widget_channel_id: nil,
        widget_enabled: nil
      },
      inviter: %Nostrum.Struct.User{
        avatar: "7c088084d173c3ab0d66fc2bd9e48dc8",
        bot: nil,
        discriminator: "2694",
        email: nil,
        id: 90_575_330_862_972_928,
        mfa_enabled: nil,
        username: "Andris",
        verified: nil
      },
      max_age: 1800,
      max_uses: 5,
      revoked: nil,
      temporary: false,
      uses: 0
    }
  ]
  @mock_deleted_message %Nostrum.Struct.Message{
    activity: nil,
    application: nil,
    attachments: [
      %Nostrum.Struct.Message.Attachment{
        filename: "1.txt",
        height: nil,
        id: 485_178_897_441_488_897,
        proxy_url:
          "https://media.discordapp.net/attachments/473537127116963841/485178897441488897/1.txt",
        size: 0,
        url: "https://cdn.discordapp.com/attachments/473537127116963841/485178897441488897/1.txt",
        width: nil
      }
    ],
    author: %Nostrum.Struct.User{
      avatar: "9141ed67386af8a4641322e153509959",
      bot: true,
      discriminator: "4848",
      email: nil,
      id: 473_537_396_399_407_104,
      mfa_enabled: nil,
      username: "Curie",
      verified: nil
    },
    channel_id: 473_537_127_116_963_841,
    content: "Something",
    edited_timestamp: nil,
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
    guild_id: 473_537_126_680_494_111,
    id: 485_178_898_057_920_552,
    mention_everyone: false,
    mention_roles: [],
    mentions: [],
    nonce: nil,
    pinned: false,
    reactions: nil,
    timestamp: "2018-08-31T20:07:43.485000+00:00",
    tts: false,
    type: 0,
    webhook_id: nil
  }

  test "Curie.Announcements.iso_to_unix/1" do
    iso = "2018-08-29T14:18:34.199000+00:00"
    assert Curie.Announcements.iso_to_unix(iso) == 1_535_552_314
    assert Curie.Announcements.iso_to_unix("None") == nil
    assert Curie.Announcements.iso_to_unix(nil) == nil
  end

  test "Curie.Announcements.join_log/2" do
    {:ok, %{embeds: [%{description: description}]} = message} =
      Curie.Announcements.join_log(@mock_invites, @invitee)

    assert String.contains?(description, "Andris invited Someone to the guild. (2)")
    Api.delete_message(message)
  end

  test "Curie.Announcements.delete_log/1" do
    not_loggable = %{@mock_deleted_message | id: 1, channel_id: 473_537_127_116_963_841}

    direct = %{@mock_deleted_message | id: 2, channel_id: 484_381_611_979_178_026, guild_id: nil}

    test1 = %{@mock_deleted_message | id: 3, channel_id: 484_377_016_037_015_564}

    for message <- [not_loggable, direct, test1] do
      GenServer.cast(Curie.MessageCache, {:add, message})
    end

    {:ok, %{embeds: [%{description: description}]} = message} =
      Curie.Announcements.delete_log(%{
        id: 3,
        channel_id: 484_377_016_037_015_564,
        guild_id: 473_537_126_680_494_111
      })

    assert Curie.Announcements.delete_log(%{
             id: 2,
             channel_id: 484_381_611_979_178_026,
             guild_id: nil
           }) == :ignore

    assert Curie.Announcements.delete_log(not_loggable) == :ignore

    assert description ==
             "#test1 Curie#4848: Something [\"1.txt\"] " <>
               "[%Nostrum.Struct.Embed{author: nil, color: 6570405, description: \"Embed\", " <>
               "fields: nil, footer: nil, image: nil, provider: nil, thumbnail: nil, " <>
               "timestamp: nil, title: nil, type: \"rich\", url: nil, video: nil}]"

    Api.delete_message(message)
  end

  test "Curie.Announcements.leave_log/1" do
    {:ok, %{embeds: [%{description: description}]} = message} =
      Curie.Announcements.leave_log(@invitee)

    assert String.starts_with?(description, @invitee.user.username)
    Api.delete_message(message)
  end

  test "stream announcement cooldown" do
    with entry when entry != nil <- Data.get(Streams, @andris) do
      Data.delete(entry)
    end

    assert Curie.Announcements.has_cooldown?(@andris) == false
    Curie.Announcements.set_cooldown(@andris)
    assert Curie.Announcements.has_cooldown?(@andris) == true

    %Streams{member: @andris}
    |> Streams.changeset(%{time: Timex.to_unix(Timex.now()) - 30_000})
    |> Data.update()

    assert Curie.Announcements.has_cooldown?(@andris) == false
  end

  test "stream announcement" do
    with entry when entry != nil <- Data.get(Streams, @andris) do
      Data.delete(entry)
    end

    {_, _, %{game: game}} =
      presence =
      {@guild, %{},
       %{
         game: %{
           type: 1,
           url: "https://www.twitch.tv/varser",
           name: "Stream announcement test..."
         },
         user: %{id: @andris}
       }}

    {:ok, %{embeds: [%Embed{} = embed]} = message} = Curie.Announcements.stream(presence)

    assert embed.description == "[#{game.name}](#{game.url})"
    assert String.contains?(embed.author.name, "started streaming!")
    assert Curie.Announcements.stream(presence) == nil

    Api.delete_message(message)
  end
end
