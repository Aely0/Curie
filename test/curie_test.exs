defmodule CurieTest do
  use ExUnit.Case, async: true

  alias Nostrum.Api

  defp add_ids(map) do
    Map.merge(map, %{
      curie_id: elem(Curie.my_id(), 1),
      general_id: Application.get_env(:curie, :channels).general,
      guild_id: Application.get_env(:curie, :guild)
    })
  end

  defp add_typo_checks(map) do
    Map.merge(map, %{
      commands: ~w/felweed rally details cat overwatch roll ping/,
      typos: ~w/falwed raly detaisls ca owervatch rol oing/,
      invalid: ~w/asdggs aly dettassasa tas weraaaa lo iogn/
    })
  end

  defp add_member_messages(%{curie_id: curie_id, guild_id: guild_id} = map) do
    Map.merge(map, %{
      message_with_member: %{
        member: %{nick: "Curie Dev"},
        guild_id: guild_id,
        author: %{id: curie_id, username: "Curie"}
      },
      message_with_member_no_nickname: %{
        member: %{nick: nil},
        guild_id: guild_id,
        author: %{id: curie_id, username: "Curie"}
      },
      message_without_member: %{
        member: nil,
        guild_id: guild_id,
        author: %{id: curie_id, username: "Curie"}
      },
      message_without_member_or_guild_id: %{
        member: nil,
        guild_id: nil,
        author: %{id: curie_id, username: "Curie"}
      }
    })
  end

  defp add_message_base(%{guild_id: guild_id} = map) do
    Map.merge(map, %{
      base_message: %{guild_id: guild_id, content: "Message Content", mentions: []}
    })
  end

  setup_all do
    Map.new()
    |> add_ids()
    |> add_typo_checks()
    |> add_member_messages()
    |> add_message_base()
  end

  describe "Curie.avatar_url/2" do
    test "check validity of formatted avatar url", %{curie_id: curie_id, guild_id: guild_id} do
      {:ok, %{user: user}} = Curie.get_member({guild_id, :id, curie_id})
      assert {:ok, response} = user |> Curie.avatar_url() |> Curie.get()
    end
  end

  describe "Curie.check_typo/2" do
    test "check slight typos againts command names", %{commands: commands, typos: typos} do
      assert typos |> Enum.map(&Curie.check_typo(&1, commands)) |> Enum.all?()
    end

    test "check invalid typos against command names", %{commands: commands, invalid: invalid} do
      assert invalid |> Enum.map(&Curie.check_typo(&1, commands)) |> Enum.all?(&(&1 == nil))
    end
  end

  describe "Curie.send|edit|embed" do
    test "send message, edit it, send embed, delete sent items", %{general_id: general_id} do
      with {:ok, message} <- Curie.send(general_id, "Message sent."),
           {:ok, message} <- Curie.edit(message, content: "Message edited."),
           {:ok, embed_message} <- Curie.embed(general_id, "Embed sent.", "yellow"),
           {:ok} <- Api.bulk_delete_messages(message.channel_id, [message.id, embed_message.id]) do
        assert true
      else
        failure -> assert false, inspect(failure)
      end
    end
  end

  describe "Curie.get/3" do
    test "check http get" do
      assert match?({:ok, _}, Curie.get("google.com"))
    end
  end

  describe "Curie.unix_to_amount/1" do
    test "parse minutes" do
      assert Timex.now()
             |> (&(Timex.to_unix(&1) - 60)).()
             |> Curie.unix_to_amount()
             |> (&(&1 == "1m")).()
    end

    test "parse hours and seconds" do
      assert Timex.now()
             |> (&(Timex.to_unix(&1) - 60 * 60 * 8 - 10)).()
             |> Curie.unix_to_amount()
             |> (&(&1 == "8h, 10s")).()
    end

    test "parse days and seconds" do
      assert Timex.now()
             |> (&(Timex.to_unix(&1) - 60 * 60 * 24 - 1)).()
             |> Curie.unix_to_amount()
             |> (&(&1 == "1d, 1s")).()
    end

    test "parse days" do
      assert Timex.now()
             |> (&(Timex.to_unix(&1) - 60 * 60 * 24 * 70)).()
             |> Curie.unix_to_amount()
             |> (&(&1 == "70d")).()
    end
  end

  describe "Curie.get_display_name/1" do
    test "with full member", %{message_with_member: message} do
      assert Curie.get_display_name(message) == "Curie Dev"
    end

    test "with no nickname", %{message_with_member_no_nickname: message} do
      assert Curie.get_display_name(message) == "Curie"
    end

    test "with no member field", %{message_without_member: message} do
      assert Curie.get_display_name(message) == "Curie Dev"
    end

    test "with no member or guild_id field", %{message_without_member_or_guild_id: message} do
      assert Curie.get_display_name(message) == "Curie"
    end
  end

  describe "Curie.get_display_name/2" do
    test "with guild and user id", %{curie_id: curie_id, guild_id: guild_id} do
      assert Curie.get_display_name(guild_id, curie_id) == "Curie Dev"
    end

    test "with invalid guild id and user id", %{curie_id: curie_id} do
      assert Curie.get_display_name(0, curie_id) == "Curie"
    end

    test "with invalid details" do
      assert Curie.get_display_name(0, 0) == "Unknown"
    end
  end

  describe "Curie.get_username/1" do
    test "wuth valid user id", %{curie_id: curie_id} do
      assert Curie.get_username(curie_id) == "Curie"
    end

    test "with invalid user id" do
      assert Curie.get_username(0) == "Unknown"
    end
  end

  describe "Curie.get_member/2" do
    test "with nickname", %{curie_id: curie_id, base_message: base} do
      {:ok, %{user: %{id: id}}} = Curie.get_member(%{base | content: "!test Curie Dev"}, 1)
      assert id == curie_id
    end

    test "with username", %{curie_id: curie_id, base_message: base} do
      {:ok, %{user: %{id: id}}} = Curie.get_member(%{base | content: "!test Curie"}, 1)
      assert id == curie_id
    end

    test "with tag", %{curie_id: curie_id, base_message: base} do
      {:ok, %{user: %{id: id}}} = Curie.get_member(%{base | content: "!test Curie#4848"}, 1)
      assert id == curie_id
    end

    test "with mention", %{curie_id: curie_id, base_message: base} do
      {:ok, %{user: %{id: id}}} = Curie.get_member(%{base | mentions: [%{id: curie_id}]}, 1)
      assert id == curie_id
    end

    test "with id", %{curie_id: curie_id, base_message: base} do
      {:ok, %{user: %{id: id}}} = Curie.get_member(%{base | content: "!test #{curie_id}"}, 1)
      assert id == curie_id
    end

    test "non matches", %{base_message: base} do
      no_match = Curie.get_member(%{base | content: "!test 1234455566777"}, 1)
      assert no_match == {:error, :member_not_found}

      no_match = Curie.get_member(%{base | content: "!test Curie#1234#1234"}, 1)
      assert no_match == {:error, :member_not_found}

      no_match = Curie.get_member(%{base | content: "!test ###############"}, 1)
      assert no_match == {:error, :member_not_found}
    end

    test "without guild", %{base_message: base} do
      error = Curie.get_member(%{base | guild_id: nil, content: "!test Curie"}, 1)
      assert error == {:error, :requires_guild_context}
    end

    test "without member", %{base_message: base} do
      error = Curie.get_member(%{base | content: "!test"}, 1)
      assert error == {:error, :no_identifier_given}
    end
  end
end
