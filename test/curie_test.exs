defmodule CurieTest do
  use ExUnit.Case, async: true

  alias Nostrum.Api

  @curie 473_537_396_399_407_104
  @general 473_537_127_116_963_841
  @guild 473_537_126_680_494_111

  test "Curie.avatar_url/2" do
    {:ok, %{user: user}} = Curie.get_member({@guild, :id, @curie})

    assert user
           |> Curie.avatar_url()
           |> Curie.get()
           |> (&match?({:ok, _}, &1)).()
  end

  test "Curie.check_typo/2" do
    commands = ~w/felweed rally details cat overwatch roll ping/
    typos = ~w/falwed raly detaisls c owervatch rol oing/
    invalid = ~w/asdggs aly dettassasa tas weraaaa lo iogn/

    assert typos |> Enum.map(&Curie.check_typo(&1, commands)) |> Enum.all?()

    assert invalid
           |> Enum.map(&Curie.check_typo(&1, commands))
           |> Enum.reject(&(&1 == nil))
           |> Enum.empty?()
  end

  test "Curie.send|edit|embed" do
    with {:ok, message} <- Curie.send(@general, "Message sent."),
         {:ok, message} <- Curie.edit(message, content: "Message edited."),
         {:ok, embed_message} <- Curie.embed(@general, "Embed sent.", "yellow"),
         {:ok} <- Api.bulk_delete_messages(message.channel_id, [message.id, embed_message.id]) do
      embed_message.embeds != []
    end
    |> assert
  end

  test "Curie.get/3" do
    assert match?({:ok, _}, Curie.get("google.com"))
    assert match?({:ok, _}, Curie.get("google.com", [], 10))
    assert match?({:error, _}, Curie.get("Random", [], 5))
  end

  test "Curie.unix_to_amount/1" do
    assert Timex.now()
           |> (&(Timex.to_unix(&1) - 60)).()
           |> Curie.unix_to_amount()
           |> (&(&1 == "1m")).()

    assert Timex.now()
           |> (&(Timex.to_unix(&1) - 60 * 60 * 8 - 10)).()
           |> Curie.unix_to_amount()
           |> (&(&1 == "8h, 10s")).()

    assert Timex.now()
           |> (&(Timex.to_unix(&1) - 60 * 60 * 24 - 1)).()
           |> Curie.unix_to_amount()
           |> (&(&1 == "1d, 1s")).()

    assert Timex.now()
           |> (&(Timex.to_unix(&1) - 60 * 60 * 24 * 70)).()
           |> Curie.unix_to_amount()
           |> (&(&1 == "70d")).()
  end

  test "Curie.get_display_name/1" do
    message_with_member = %{
      member: %{nick: "Curie Dev"},
      guild_id: @guild,
      author: %{id: @curie, username: "Curie"}
    }

    message_with_member_no_nickname = %{
      member: %{nick: nil},
      guild_id: @guild,
      author: %{id: @curie, username: "Curie"}
    }

    message_without_member = %{
      member: nil,
      guild_id: @guild,
      author: %{id: @curie, username: "Curie"}
    }

    message_without_member_or_guild_id = %{
      member: nil,
      guild_id: nil,
      author: %{id: @curie, username: "Curie"}
    }

    assert Curie.get_display_name(message_with_member) == "Curie Dev"
    assert Curie.get_display_name(message_with_member_no_nickname) == "Curie"
    assert Curie.get_display_name(message_without_member) == "Curie Dev"
    assert Curie.get_display_name(message_without_member_or_guild_id) == "Curie"
  end

  test "Curie.get_display_name/2" do
    assert Curie.get_display_name(@guild, @curie) == "Curie Dev"
    assert Curie.get_display_name(0, @curie) == "Unknown"
  end

  test "Curie.get_username/1" do
    assert Curie.get_username(@curie) == "Curie"
    assert Curie.get_username(0) == "Unknown"
  end

  test "Curie.get_member/2" do
    message_base = %{guild_id: @guild, content: "Message Content", mentions: []}

    {:ok, %{user: %{id: with_nickname}}} =
      Curie.get_member(%{message_base | content: "!test Curie Dev"}, 1)

    assert with_nickname == @curie

    {:ok, %{user: %{id: with_name}}} =
      Curie.get_member(%{message_base | content: "!test Curie"}, 1)

    assert with_name == @curie

    {:ok, %{user: %{id: with_tag}}} =
      Curie.get_member(%{message_base | content: "!test Curie#4848"}, 1)

    assert with_tag == @curie

    {:ok, %{user: %{id: with_mention}}} =
      Curie.get_member(%{message_base | mentions: [%{id: @curie}]}, 1)

    assert with_mention == @curie

    {:ok, %{user: %{id: with_id}}} =
      Curie.get_member(%{message_base | content: "!test #{@curie}"}, 1)

    assert with_id == @curie

    no_match = Curie.get_member(%{message_base | content: "!test 1234455566777"}, 1)
    assert no_match == {:error, :member_not_found}

    no_match = Curie.get_member(%{message_base | content: "!test Curie#1234#1234"}, 1)
    assert no_match == {:error, :member_not_found}

    no_match = Curie.get_member(%{message_base | content: "!test ###############"}, 1)
    assert no_match == {:error, :member_not_found}

    without_guild = %{guild_id: nil, content: "!test Curie", mentions: []}
    assert Curie.get_member(without_guild, 1) == {:error, :requires_guild_context}

    without_member = %{guild_id: @guild, content: "!test", mentions: []}
    assert Curie.get_member(without_member, 1) == {:error, :no_identifier_given}
  end
end
