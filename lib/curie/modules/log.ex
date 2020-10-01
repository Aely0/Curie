defmodule Curie.Log do
  @moduledoc """
  Logged guild events pushed to guild log channel.
  """

  import Nostrum.Snowflake, only: [is_snowflake: 1]

  alias Nostrum.Struct.{Guild, Invite}
  alias Nostrum.Struct.Event.MessageDelete
  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Api

  alias Curie.MessageCache

  @invisible Application.get_env(:curie, :channels).invisible
  @logs Application.get_env(:curie, :channels).logs

  @spec iso_to_unix(String.t()) :: non_neg_integer | nil
  def iso_to_unix(iso) do
    case Timex.parse(iso, "{ISO:Extended}") do
      {:ok, datetime} -> Timex.to_unix(datetime)
      _unable_to_parse -> nil
    end
  end

  @spec join(Guild.id() | [Invite.t()], Member.t()) :: Curie.message_result() | []
  def join(guild_id, %{user: %{username: invitee}} = member) when is_snowflake(guild_id) do
    case Api.get_guild_invites(guild_id) do
      {:ok, invites} when invites != [] ->
        join(invites, member)

      _no_invites ->
        "#{invitee} joined with a one time invite. #{Curie.time_now()}"
        |> (&Curie.embed(@logs, &1, "dblue")).()
    end
  end

  def join(invites, %{user: %{username: invitee}}) when is_list(invites) do
    with used when used != [] <- Enum.filter(invites, &(&1.uses > 0)),
         %Invite{} = %{inviter: %{username: inviter}} <-
           Enum.max_by(used, &iso_to_unix(&1.created_at), fn -> nil end) do
      "#{inviter} invited #{invitee} to the guild. (#{length(invites)}) #{Curie.time_now()}"
      |> (&Curie.embed(@logs, &1, "dblue")).()
    end
  end

  @spec delete(MessageDelete.t()) :: Curie.message_result() | :ignore | {:error, any}
  def delete(%{guild_id: guild_id, channel_id: channel_id} = deleted_message) do
    with true <- channel_id not in [@invisible, @logs] and guild_id != nil,
         {:ok, [message | _] = messages} <- MessageCache.get(deleted_message),
         {:ok, %{name: channel_name}} <- Api.get_channel(channel_id) do
      %{username: name, discriminator: disc} =
        Map.get(message, :author) || Map.get(message, :user)

      details =
        for %{content: content, attachments: files, embeds: embeds} <- messages do
          content = if content == "", do: "No Content", else: content
          files = if files != [], do: " " <> (files |> Enum.map(& &1.filename) |> inspect())
          embeds = if embeds != [], do: " " <> inspect(embeds)
          "#{content}#{files}#{embeds}"
        end
        |> Enum.join(", edit: ")

      "##{channel_name} #{name}##{disc}: #{details}"
      |> (&Curie.embed(@logs, &1, "red")).()
    else
      false ->
        :ignore

      {:error, :not_found} ->
        {:ok, %{name: channel_name}} = Api.get_channel(channel_id)

        "Message deleted in ##{channel_name}"
        |> (&Curie.embed(@logs, &1, "red")).()

      {:error, reason} ->
        "Delete log failed (#{inspect(reason)})"
        |> (&Curie.embed(@logs, &1, "red")).()
    end
  end

  @spec leave(Member.t()) :: Curie.message_result()
  def leave(%{user: %{username: name}}) do
    case :calendar.local_time() do
      {_, {0, 0, _}} ->
        "#{name} was pruned for 30 days of inactivity #{Curie.time_now("%d-%m-%Y")}"

      _time ->
        "#{name} left the guild. #{Curie.time_now()}"
    end
    |> (&Curie.embed(@logs, &1, "dblue")).()
  end
end
