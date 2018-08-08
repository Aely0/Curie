defmodule Curie.Announcements do
  alias Nostrum.Cache.{ChannelCache, UserCache}
  alias Nostrum.Struct.{Guild, Message, User}
  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Api

  alias Curie.Data.Streams
  alias Curie.Data

  import Nostrum.Struct.Embed

  @notify 141_160_537_672_122_368

  @spec iso_to_unix(String.t()) :: non_neg_integer
  def iso_to_unix(iso), do: iso |> Timex.parse!("{ISO:Extended}") |> Timex.to_unix()

  @spec join_log(Guild.id(), Member.t()) :: Message.t() | no_return
  def join_log(guild_id, member) do
    with {:ok, invites} <- Api.get_guild_invites(guild_id),
         true <- invites != [] do
      latest =
        invites
        |> Enum.filter(&(&1.uses > 0))
        |> Enum.max_by(&(&1.created_at |> iso_to_unix()), fn -> nil end)

      if latest != nil do
        ("#{latest.inviter.username} invited #{member.user.username} " <>
           "to the server. (#{length(invites)}) #{Curie.time_now()}")
        |> (&Curie.embed(@notify, &1, "dblue")).()
      end
    else
      _no_invites ->
        "#{member.user.username} joined with a one time invite. #{Curie.time_now()}"
        |> (&Curie.embed(@notify, &1, "dblue")).()
    end
  end

  @spec delete_log(%{channel_id: Message.channel_id()}) :: Message.t() | no_return
  def delete_log(%{channel_id: channel_id}) do
    if channel_id != @notify do
      channel =
        ChannelCache.get!(channel_id)
        |> (&if(&1.name, do: "#" <> &1.name, else: "#DM")).()

      Curie.embed(@notify, "Message got deleted in #{channel}", "red")
    end
  end

  @spec leave_log(Member.t()) :: Message.t()
  def leave_log(member) do
    content =
      if Timex.local() |> Timex.format!("%H%M", :strftime) == "0000",
        do: "#{member.user.username} was pruned for 30 days of inactivity #{Curie.time_now()}",
        else: "#{member.user.username} left. #{Curie.time_now()}"

    Curie.embed(@notify, content, "dblue")
  end

  @spec has_cooldown?(User.id()) :: boolean
  def has_cooldown?(member) do
    case Data.get(Streams, member) do
      %{time: time} ->
        (Timex.local() |> Timex.to_unix()) - time <= 21600

      nil ->
        false
    end
  end

  @spec set_cooldown(User.id()) :: no_return
  def set_cooldown(member) do
    case Data.get(Streams, member) do
      nil ->
        %Streams{member: member}

      cooldown ->
        cooldown
    end
    |> Streams.changeset(%{time: Timex.local() |> Timex.to_unix()})
    |> Data.insert_or_update()
  end

  @spec stream(%{game: String.t(), user: %{id: User.id()}}) :: no_return
  def stream(%{game: game, user: %{id: member}} = _presence) do
    if game != nil and game.type == 1 and !has_cooldown?(member) do
      twitch_id = Application.get_env(:curie, :twitch)
      channel_name = game.url |> String.split("/") |> List.last()
      url = "https://api.twitch.tv/kraken/channels/#{channel_name}/?client_id=#{twitch_id}"

      with {:ok, %{body: body}} <- Curie.get(url) do
        details = Poison.decode!(body)
        member = UserCache.get!(member)
        content = "#{member.username} started streaming!"

        %Nostrum.Struct.Embed{}
        |> put_author(content, nil, Curie.avatar_url(member))
        |> put_description("[#{game.name}](#{game.url})")
        |> put_color(Curie.color("purple"))
        |> put_field("Playing:", details["game"], true)
        |> put_field("Channel:", "Twitch.tv/" <> details["display_name"], true)
        |> put_thumbnail(details["logo"])
        |> (&Curie.send(99_304_946_280_701_952, embed: &1)).()

        set_cooldown(member.id)
      end
    end
  end
end
