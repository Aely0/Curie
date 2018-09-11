defmodule Curie.Colors do
  use Curie.Commands

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

  def get_member_roles(member, guild) do
    GuildCache.select!(guild, & &1.members[member].roles)
  end

  def get_role_color(color_name, guild) do
    GuildCache.select!(guild, & &1.roles[@color_roles[color_name]].color)
  end

  def remove_all_color_roles(member, guild) do
    member_roles = get_member_roles(member, guild)
    color_roles = Map.values(@color_roles)

    for role <- member_roles do
      if role in color_roles do
        Api.remove_guild_member_role(guild, member, role)
      end
    end
  end

  @spec color_preview(String.t(), map()) :: no_return()
  def color_preview(color_name, %{channel_id: channel, guild_id: guild}) do
    color_value = get_role_color(color_name, guild)
    color_id = @color_roles[color_name]
    curie = Curie.my_id()

    Api.add_guild_member_role(guild, curie, color_id)
    Curie.embed(channel, color_name, color_value)
    Api.remove_guild_member_role(guild, curie, color_id)
  end

  @spec confirm_transaction(String.t(), map()) :: no_return()
  def confirm_transaction(color_name, %{
        author: %{id: member, username: name},
        channel_id: channel,
        guild_id: guild
      }) do
    remove_all_color_roles(member, guild)
    Api.add_guild_member_role(guild, member, @color_roles[color_name])
    Api.add_guild_member_role(guild, member, @snowflakes)
    Currency.change_balance(:deduct, member, 500)
    Curie.embed(channel, "#{name} acquired #{color_name}!", get_role_color(color_name, guild))
  end

  @impl true
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

  @impl true
  def command(call) do
    check_typo(call, @check_typo.command, &command/1)
  end

  @impl true
  def subcommand({"preview", message, [color_name | _rest]}) do
    case parse_color_name(color_name) do
      nil -> Curie.embed(message, "Color not recognized.", "red")
      color -> color_preview(color, message)
    end
  end

  @impl true
  def subcommand({"remove", %{author: %{id: member}, guild_id: guild} = message, _args}) do
    if Storage.whitelisted?(message) do
      remove_all_color_roles(member, guild)
      Curie.embed(message, "Color associated roles were removed.", "green")
    else
      Storage.whitelist_message(message)
    end
  end

  @impl true
  def subcommand(_invalid_arguments), do: nil
end
