defmodule Curie.Generic.Details do
  use Bitwise

  alias Data.Details

  alias Nostrum.Cache.{GuildCache, PresenceCache}
  alias Nostrum.Struct.Guild.{Member, Role}
  alias Nostrum.Struct.{Guild, User}
  alias Nostrum.Api

  @spec get_cached({Member.t(), Guild.id()}) :: map()
  defp get_cached({%{user: %{id: id}} = member, guild_id}) do
    %{id: id, member: member, guild_id: guild_id, presence: PresenceCache.get(id, guild_id)}
  end

  @spec get_stored(%{id: User.id()}) :: map()
  defp get_stored(%{id: id} = details) do
    Map.put(details, :stored, Curie.Storage.get_details(id))
  end

  @spec get_display_name(%{member: Member.t()}) :: map()
  defp get_display_name(%{member: %{nick: nick, user: %{username: username}}} = details) do
    Map.put(details, :display_name, nick || username)
  end

  @spec get_discord_tag(%{member: Member.t()}) :: map()
  defp get_discord_tag(%{member: %{user: %{username: username, discriminator: disc}}} = details) do
    Map.put(details, :discord_tag, "#{username}##{disc}")
  end

  @spec get_status(%{presence: map(), stored: Details.t()}) :: map()
  defp get_status(%{presence: presence, stored: stored} = details) do
    %{
      offline_since: offline_since,
      last_status_change: last_status_change,
      last_status_type: last_status_type
    } = stored

    case presence do
      {:ok, %{status: :dnd}} ->
        if last_status_change && last_status_type == "dnd",
          do: "Do Not Disturb for " <> Curie.unix_to_amount(last_status_change),
          else: "Do Not Disturb"

      {:ok, %{status: status}} when status != :offline ->
        status_name = status |> Atom.to_string() |> String.capitalize()

        if last_status_change && last_status_type == to_string(status),
          do: status_name <> " for " <> Curie.unix_to_amount(last_status_change),
          else: status_name

      _offline_or_not_found ->
        if offline_since,
          do: "Offline for #{Curie.unix_to_amount(offline_since)}",
          else: "Never seen online"
    end
    |> (&Map.put(details, :status, &1)).()
  end

  @spec get_activity(%{presence: map()}) :: map()
  defp get_activity(%{presence: presence} = details) do
    case presence do
      {:ok, %{game: %{name: name, type: type, timestamps: %{start: start}}}} ->
        %{0 => "Playing ", 1 => "Streaming ", 2 => "Listening to "}[type] <>
          name <> " for " <> Curie.unix_to_amount(trunc(start / 1000))

      {:ok, %{status: :online}} ->
        "Stuff and things"

      _offline_idle_dnd ->
        [
          "Sailing the 7 seas",
          "Furnishing their evil lair",
          "Dreaming about cheese...",
          "Watching paint dry",
          "Pretending to be a potato",
          "Praising the sun",
          "Doing a barrel roll",
          "Taking a 14h nap"
        ]
        |> Enum.random()
    end
    |> (&Map.put(details, :activity, &1)).()
  end

  @spec get_last_spoke(%{stored: Details.t()}) :: map()
  defp get_last_spoke(%{stored: %{spoke: last_spoke}} = details) do
    if last_spoke do
      Curie.unix_to_amount(last_spoke) <> " ago"
    else
      "Never"
    end
    |> (&Map.put(details, :last_spoke, &1)).()
  end

  @spec get_in_channel(%{stored: Details.t()}) :: map()
  defp get_in_channel(%{stored: %{channel: in_channel}} = details) do
    Map.put(details, :in_channel, in_channel || "None")
  end

  @spec get_roles(%{member: %{roles: [Role.id()]}, guild_id: Guild.id()}) :: map()
  defp get_roles(%{member: %{roles: roles}, guild_id: guild_id} = details) do
    GuildCache.get!(guild_id).roles
    |> Map.values()
    |> Enum.filter(&(&1.id in roles))
    |> Enum.map_join(", ", & &1.name)
    |> (&if(&1 == "", do: "None", else: &1)).()
    |> (&Map.put(details, :roles, &1)).()
  end

  @spec get_guild_joined(%{id: User.id(), member: Member.t(), guild_id: Guild.id()}) :: map()
  defp get_guild_joined(%{id: id, member: %{joined_at: joined_at}, guild_id: guild_id} = details) do
    (joined_at || Api.get_guild_member!(guild_id, id).joined_at)
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)
    |> (&Map.put(details, :guild_joined, &1)).()
  end

  @spec get_account_created(%{member: Member.t()}) :: map()
  defp get_account_created(%{member: %{user: %{id: id}}} = details) do
    ((id >>> 22) + 1_420_070_400_000)
    |> Timex.from_unix(:millisecond)
    |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)
    |> (&Map.put(details, :account_created, &1)).()
  end

  @spec formatted_string(map()) :: String.t()
  defp formatted_string(details) do
    """
    Display Name: #{details.display_name}
    Member: #{details.discord_tag}
    Status: #{details.status}
    Activity: #{details.activity}
    Last spoke: #{details.last_spoke}
    In channel: #{details.in_channel}
    ID: #{details.member.user.id}
    Roles: #{details.roles}
    Guild joined: #{details.guild_joined}
    Account created: #{details.account_created}
    """
  end

  @spec get(Member.t(), Guild.id()) :: String.t()
  def get(member, guild_id) do
    {member, guild_id}
    |> get_cached()
    |> get_stored()
    |> get_display_name()
    |> get_discord_tag()
    |> get_status()
    |> get_activity()
    |> get_last_spoke()
    |> get_in_channel()
    |> get_roles()
    |> get_account_created()
    |> get_guild_joined()
    |> formatted_string()
  end
end
