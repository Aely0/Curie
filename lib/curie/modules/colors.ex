defmodule Curie.Colors do
  @moduledoc """
  Color roles as guild currency purchasable reward.
  """

  use Curie.Commands

  alias Curie.{Currency, Storage}
  alias Nostrum.Api
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Struct.Guild.Role
  alias Nostrum.Struct.{Guild, Message, User}

  @check_typo ~w/color color_preview color_remove/
  @color_roles Application.compile_env(:curie, :color_roles)
  @snowflakes @color_roles["snowflakes"]
  @color_cost 500

  @spec parse_color_name(String.t()) :: String.t() | nil
  def parse_color_name(color_name) do
    if Map.has_key?(@color_roles, color_name),
      do: color_name,
      else: Curie.check_typo(color_name, Map.keys(@color_roles))
  end

  @spec get_member_roles(User.id(), Guild.id()) :: [Role.t()] | no_return
  def get_member_roles(member_id, guild_id) do
    GuildCache.select!(guild_id, & &1.members[member_id].roles)
  end

  @spec get_role_color(String.t(), Guild.id()) :: Role.color() | no_return
  def get_role_color(color_name, guild_id) do
    GuildCache.select!(guild_id, & &1.roles[@color_roles[color_name]].color)
  end

  @spec remove_all_color_roles(User.id(), Guild.id()) :: :ok
  def remove_all_color_roles(member_id, guild_id) do
    member_roles = get_member_roles(member_id, guild_id)
    color_roles = Map.values(@color_roles)

    for role <- member_roles do
      if role in color_roles do
        Api.remove_guild_member_role(guild_id, member_id, role)
      end
    end

    :ok
  end

  @spec color_preview(String.t(), Message.t()) :: :ok
  def color_preview(color_name, %{channel_id: channel_id, guild_id: guild_id}) do
    color_value = get_role_color(color_name, guild_id)
    color_id = @color_roles[color_name]
    {:ok, curie_id} = Curie.my_id()

    Api.add_guild_member_role(guild_id, curie_id, color_id)
    Curie.embed(channel_id, color_name, color_value)
    Api.remove_guild_member_role(guild_id, curie_id, color_id)

    :ok
  end

  @spec confirm_transaction(String.t(), Message.t()) :: :ok
  def confirm_transaction(color_name, %{author: %{id: member_id}, guild_id: guild_id} = message) do
    color = get_role_color(color_name, guild_id)
    member_name = Curie.get_display_name(message)

    remove_all_color_roles(member_id, guild_id)
    Api.add_guild_member_role(guild_id, member_id, @color_roles[color_name])
    Api.add_guild_member_role(guild_id, member_id, @snowflakes)

    Currency.change_balance(:deduct, member_id, @color_cost)
    Curie.embed(message, "#{member_name} acquired #{color_name}!", color)

    :ok
  end

  @impl Curie.Commands
  def command({"color", %{author: %{id: member_id}} = message, [color_name | _rest]}) do
    case parse_color_name(color_name) do
      nil ->
        Curie.embed(message, "Color not recognized", "red")

      color ->
        with true <- Storage.whitelisted?(member_id),
             {:ok, balance} when balance >= @color_cost <- Currency.get_balance(member_id) do
          confirm_transaction(color, message)
        else
          false ->
            Storage.whitelist_message(message)

          {:ok, _balance} ->
            Curie.embed(message, "Color change costs #{@color_cost}#{@tempest}", "red")

          {:error, _error} ->
            Curie.embed(message, "No balance seems to exist?", "red")
        end
    end
  end

  @impl Curie.Commands
  def command({"color_preview", message, [color_name | _rest]}) do
    case parse_color_name(color_name) do
      nil -> Curie.embed(message, "Color not recognized", "red")
      color -> color_preview(color, message)
    end
  end

  @impl Curie.Commands
  def command({"color_remove", %{author: %{id: member_id}, guild_id: guild_id} = message, _args}) do
    if Storage.whitelisted?(message) do
      remove_all_color_roles(member_id, guild_id)
      Curie.embed(message, "Color associated roles were removed", "green")
    else
      Storage.whitelist_message(message)
    end
  end

  @impl Curie.Commands
  def command(call) do
    Commands.check_typo(call, @check_typo, &command/1)
  end
end
