defmodule Curie.Colors do
  use Curie.Commands

  alias Nostrum.Struct.{Guild, User}
  alias Nostrum.Struct.Guild.Role
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Api

  alias Curie.{Currency, Storage}

  @check_typo %{command: ~w/color/, subcommand: ~w/remove preview/}
  @color_roles Application.get_env(:curie, :color_roles)
  @snowflakes @color_roles["snowflakes"]

  @spec parse_color_name(String.t()) :: String.t() | nil
  def parse_color_name(color_name) do
    if Map.has_key?(@color_roles, color_name),
      do: color_name,
      else: Curie.check_typo(color_name, Map.keys(@color_roles))
  end

  @spec get_member_roles(User.id(), Guild.id()) :: [Role.t()]
  def get_member_roles(member_id, guild_id) do
    GuildCache.select!(guild_id, & &1.members[member_id].roles)
  end

  @spec get_role_color(String.t(), Guild.id()) :: Role.color()
  def get_role_color(color_name, guild_id) do
    GuildCache.select!(guild_id, & &1.roles[@color_roles[color_name]].color)
  end

  @spec remove_all_color_roles(User.id(), Guild.id()) :: no_return()
  def remove_all_color_roles(member_id, guild_id) do
    member_roles = get_member_roles(member_id, guild_id)
    color_roles = Map.values(@color_roles)

    for role <- member_roles do
      if role in color_roles do
        Api.remove_guild_member_role(guild_id, member_id, role)
      end
    end
  end

  @spec color_preview(String.t(), map()) :: no_return()
  def color_preview(color_name, %{channel_id: channel_id, guild_id: guild_id}) do
    color_value = get_role_color(color_name, guild_id)
    color_id = @color_roles[color_name]
    {:ok, curie_id} = Curie.my_id()

    Api.add_guild_member_role(guild_id, curie_id, color_id)
    Curie.embed(channel_id, color_name, color_value)
    Api.remove_guild_member_role(guild_id, curie_id, color_id)
  end

  @spec confirm_transaction(String.t(), map()) :: no_return()
  def confirm_transaction(color_name, %{author: %{id: member_id}, guild_id: guild_id} = message) do
    color = get_role_color(color_name, guild_id)
    member_name = Curie.get_display_name(message)
    remove_all_color_roles(member_id, guild_id)
    Api.add_guild_member_role(guild_id, member_id, @color_roles[color_name])
    Api.add_guild_member_role(guild_id, member_id, @snowflakes)
    Currency.change_balance(:deduct, member_id, 500)
    Curie.embed(message, "#{member_name} acquired #{color_name}!", color)
  end

  @impl Curie.Commands
  def command({"color", message, [color_name | rest]}) do
    case parse_color_name(color_name) do
      nil ->
        case Curie.check_typo(color_name, @check_typo.subcommand) do
          nil -> Curie.embed(message, "Color not recognized.", "red")
          subcall -> subcommand({subcall, message, rest})
        end

      color ->
        if Storage.whitelisted?(message),
          do: confirm_transaction(color, message),
          else: Storage.whitelist_message(message)
    end
  end

  @impl Curie.Commands
  def command(call) do
    check_typo(call, @check_typo.command, &command/1)
  end

  @impl Curie.Commands
  def subcommand({"preview", message, [color_name | _rest]}) do
    case parse_color_name(color_name) do
      nil -> Curie.embed(message, "Color not recognized.", "red")
      color -> color_preview(color, message)
    end
  end

  @impl Curie.Commands
  def subcommand({"remove", %{author: %{id: member_id}, guild_id: guild_id} = message, _args}) do
    if Storage.whitelisted?(message) do
      remove_all_color_roles(member_id, guild_id)
      Curie.embed(message, "Color associated roles were removed.", "green")
    else
      Storage.whitelist_message(message)
    end
  end

  @impl Curie.Commands
  def subcommand(_invalid_arguments), do: nil
end
