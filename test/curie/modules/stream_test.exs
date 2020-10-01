defmodule StreamTest do
  use ExUnit.Case, async: true

  alias Nostrum.Api

  alias Curie.Data
  alias Curie.Data.Streams
  alias Curie.Stream

  defp add_ids(map) do
    Map.merge(map, %{
      member_id: Application.get_env(:curie, :owner),
      guild_id: Application.get_env(:curie, :guild)
    })
  end

  defp add_stream_cooldown(map) do
    Map.merge(map, %{stream_cooldown: Application.get_env(:curie, :stream_message_cooldown)})
  end

  defp add_stream_presence(%{guild_id: guild_id, member_id: member_id} = map) do
    {:ok, headers} = Stream.create_headers()

    channel_url = "https://api.twitch.tv/helix/streams?first=1"
    {:ok, %{body: body}} = Curie.get(channel_url, headers)
    {:ok, %{"data" => [channel | _]}} = Jason.decode(body)

    game_url = "https://api.twitch.tv/helix/games?id=#{channel["game_id"]}"
    {:ok, %{body: body}} = Curie.get(game_url, headers)
    {:ok, %{"data" => [%{"name" => stream_game} | _]}} = Jason.decode(body)

    Map.merge(map, %{
      stream_presence:
        {guild_id, %{},
         %{
           game: %{
             type: 1,
             details: channel["title"],
             state: stream_game,
             url: "https://www.twitch.tv/" <> channel["user_name"]
           },
           user: %{id: member_id}
         }}
    })
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
    |> add_stream_cooldown()
    |> add_stream_presence()
  end

  describe "Stream announcement cooldowns" do
    test "set cooldown and check for it", %{member_id: member_id} do
      clear_stream_cooldown(member_id)

      Stream.set_cooldown(%{channel_id: 0, id: 0}, member_id)

      {:ok, stream} = Stream.stored_stream_message(member_id)

      assert Stream.has_cooldown?(stream)
    end

    test "set and check for expired cooldown", %{
      member_id: member_id,
      stream_cooldown: stream_cooldown
    } do
      clear_stream_cooldown(member_id)

      %Streams{member: member_id}
      |> Streams.changeset(%{
        time: Timex.to_unix(Timex.now()) - (stream_cooldown + 1),
        channel_id: 0,
        message_id: 0
      })
      |> Data.insert()

      {:ok, stream} = Stream.stored_stream_message(member_id)

      assert !Stream.has_cooldown?(stream)
    end
  end

  describe "Stream.stream/1" do
    test "check stream embed content",
         %{member_id: member_id, stream_presence: {guild_id, old, %{game: game} = new} = presence} do
      clear_stream_cooldown(member_id)

      %{embeds: [embed]} = Stream.stream(presence)

      # Embed title "#{member_name} started streaming!"
      assert String.contains?(embed.author.name, "started streaming!")

      # Clickable link leading to member's Twitch page
      assert embed.description == "[#{game.details}](#{game.url})"

      # Stream message getting updated
      new_presence = {guild_id, old, put_in(new.game.details, "New Title")}

      %{embeds: [embed]} = message = Stream.stream(new_presence)

      assert embed.description == "[New Title](#{game.url})"

      Api.delete_message(message)
    end
  end
end
