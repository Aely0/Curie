defmodule Curie.Generic.Details do
  @moduledoc """
  Guild member info command.
  """

  use Bitwise

  alias Data.Details, as: StoredDetails
  alias Nostrum.Api
  alias Nostrum.Cache.{GuildCache, PresenceCache}
  alias Nostrum.Struct.{Guild, User}
  alias Nostrum.Struct.Guild.Member

  defstruct [
    :id,
    :member,
    :guild_id,
    :presence,
    :stored,
    :display_name,
    :discord_tag,
    :sessions,
    :status,
    :activity,
    :last_spoke,
    :in_channel,
    :roles,
    :guild_joined,
    :account_created
  ]

  @type cached_presence :: {:error, :presence_not_found} | {:ok, map}

  @type t :: %__MODULE__{
          id: User.id(),
          member: Member.t(),
          presence: cached_presence,
          stored: StoredDetails.t(),
          display_name: String.t(),
          discord_tag: String.t(),
          sessions: String.t(),
          status: String.t(),
          activity: String.t(),
          last_spoke: String.t(),
          in_channel: String.t(),
          roles: String.t(),
          guild_joined: String.t(),
          account_created: String.t()
        }

  @self __MODULE__

  @activity_prefix %{
    0 => "Playing ",
    1 => "Streaming ",
    2 => "Listening to ",
    5 => "Competing in "
  }

  @spec capitalize(atom) :: String.t()
  defp capitalize(atom), do: atom |> Atom.to_string() |> String.capitalize()

  @spec get_cached({Member.t(), Guild.id()}) :: @self.t()
  defp get_cached({%{user: %{id: id}} = member, guild_id}) do
    struct(@self,
      id: id,
      member: member,
      guild_id: guild_id,
      presence: PresenceCache.get(id, guild_id)
    )
  end

  @spec get_stored(@self.t()) :: @self.t()
  defp get_stored(%{id: id} = details) do
    struct(details, stored: Curie.Storage.get_details(id))
  end

  @spec get_display_name(@self.t()) :: @self.t()
  defp get_display_name(%{member: %{nick: nick, user: %{username: username}}} = details) do
    struct(details, display_name: nick || username)
  end

  @spec get_discord_tag(@self.t()) :: @self.t()
  defp get_discord_tag(%{member: %{user: %{username: username, discriminator: disc}}} = details) do
    struct(details, discord_tag: "#{username}##{disc}")
  end

  @spec get_sessions(@self.t()) :: @self.t()
  defp get_sessions(%{presence: {:ok, %{client_status: sessions}}} = details) do
    sessions =
      Enum.map(sessions, fn
        {platform, :dnd} ->
          "#{capitalize(platform)}: Do Not Disturb"

        {platform, status} ->
          "#{capitalize(platform)}: #{capitalize(status)}"
      end)
      |> case do
        [] -> "None"
        sessions -> "(#{Enum.join(sessions, ", ")})"
      end

    struct(details, sessions: sessions)
  end

  defp get_sessions(%{presence: {:error, :presence_not_found}} = details) do
    struct(details, sessions: "None")
  end

  @spec get_status(@self.t()) :: @self.t()
  defp get_status(%{presence: presence, stored: stored} = details) do
    %{
      offline_since: offline_since,
      last_status_change: last_status_change,
      last_status_type: last_status_type
    } = stored

    status =
      case presence do
        {:ok, %{status: :dnd}} ->
          if last_status_change && last_status_type == "dnd",
            do: "Do Not Disturb for " <> Curie.unix_to_amount(last_status_change),
            else: "Do Not Disturb"

        {:ok, %{status: status}} when status != :offline ->
          status_name = capitalize(status)

          if last_status_change && last_status_type == to_string(status),
            do: status_name <> " for " <> Curie.unix_to_amount(last_status_change),
            else: status_name

        _offline_or_not_found ->
          if offline_since,
            do: "Offline for #{Curie.unix_to_amount(offline_since)}",
            else: "Never seen online"
      end

    struct(details, status: status)
  end

  @spec get_activity(@self.t()) :: @self.t()
  defp get_activity(%{presence: presence} = details) do
    activity =
      case presence do
        {:ok, %{game: %{emoji: %{name: emoji}, state: state, type: 4}}} ->
          emoji <> " " <> String.capitalize(state)

        {:ok, %{game: %{state: state, type: 4}}} ->
          String.capitalize(state)

        {:ok, %{game: %{name: name, type: type, timestamps: %{start: start}}}} ->
          @activity_prefix[type] <> name <> " for " <> Curie.unix_to_amount(trunc(start / 1000))

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

    struct(details, activity: activity)
  end

  @spec get_last_spoke(@self.t()) :: @self.t()
  defp get_last_spoke(%{stored: %{spoke: last_spoke}} = details) do
    last_spoke =
      if last_spoke,
        do: Curie.unix_to_amount(last_spoke) <> " ago",
        else: "Never"

    struct(details, last_spoke: last_spoke)
  end

  @spec get_in_channel(@self.t()) :: @self.t()
  defp get_in_channel(%{stored: %{channel: in_channel}} = details) do
    struct(details, in_channel: in_channel || "None")
  end

  @spec get_roles(@self.t()) :: @self.t()
  defp get_roles(%{member: %{roles: roles}, guild_id: guild_id} = details) do
    GuildCache.get!(guild_id).roles
    |> Map.values()
    |> Enum.filter(&(&1.id in roles))
    |> Enum.map_join(", ", & &1.name)
    |> (&if(&1 == "", do: "None", else: &1)).()
    |> (&struct(details, roles: &1)).()
  end

  @spec get_guild_joined(@self.t()) :: @self.t()
  defp get_guild_joined(%{id: id, member: %{joined_at: joined_at}, guild_id: guild_id} = details) do
    (joined_at || Api.get_guild_member!(guild_id, id).joined_at)
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)
    |> (&struct(details, guild_joined: &1)).()
  end

  @spec get_account_created(@self.t()) :: @self.t()
  defp get_account_created(%{member: %{user: %{id: id}}} = details) do
    ((id >>> 22) + 1_420_070_400_000)
    |> Timex.from_unix(:millisecond)
    |> Timex.format!("%Y-%m-%d %H:%M:%S UTC", :strftime)
    |> (&struct(details, account_created: &1)).()
  end

  @spec formatted_string(@self.t()) :: String.t()
  defp formatted_string(details) do
    """
    Display Name: #{details.display_name}
    Member: #{details.discord_tag}
    Sessions: #{details.sessions}
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
    |> get_sessions()
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
