defmodule Curie.Colors do
  use Curie.Commands

  alias Nostrum.Struct.User
  alias Nostrum.Api

  alias Curie.Currency

  @check_typo %{command: ~w/color/, subcommand: ~w/remove preview/}
  @color_roles Application.get_env(:curie, :color_roles)
  @special_snowflake 371_732_667_080_638_466

  @spec get_color(String.t()) :: String.t() | nil
  def get_color(color) do
    color
    |> String.downcase()
    |> String.capitalize()
    |> (&if(Map.has_key?(@color_roles, &1), do: &1)).()
  end

  @spec fallback(String.t(), map(), [String.t()]) :: no_return()
  def fallback("command", message, args) do
    case Curie.check_typo(List.first(args), Map.keys(@color_roles)) do
      nil ->
        subcommand({List.first(args), message, args})

      match ->
        args
        |> List.replace_at(0, match)
        |> (&command({"color", message, &1})).()
    end
  end

  def fallback("subcommand", message, args) do
    case Curie.check_typo(Enum.at(args, 1), Map.keys(@color_roles)) do
      nil ->
        Curie.embed(message, "Color not recognized.", "red")

      match ->
        args
        |> List.replace_at(1, match)
        |> (&subcommand({"preview", message, &1})).()
    end
  end

  @spec color_preview(String.t(), map()) :: no_return()
  def color_preview(color, %{guild_id: guild_id} = message) do
    me = Nostrum.Cache.Me.get().id

    color_role =
      guild_id
      |> Api.get_guild_roles!()
      |> Enum.find(&(&1.id == @color_roles[color]))

    Api.add_guild_member_role(guild_id, me, @color_roles[color])
    Curie.embed(message, color, color_role.color)
    Api.remove_guild_member_role(guild_id, me, @color_roles[color])
  end

  @spec confirm_transaction(String.t(), User.id(), map()) :: no_return()
  def confirm_transaction(color, member, %{guild_id: guild_id} = message) do
    member_roles = Api.get_guild_member!(guild_id, member).roles
    color_roles = Map.values(@color_roles)

    for role <- member_roles do
      if role in color_roles, do: Api.remove_guild_member_role(guild_id, member, role)
    end

    if @special_snowflake not in member_roles,
      do: Api.add_guild_member_role(guild_id, member, @special_snowflake)

    Api.add_guild_member_role(guild_id, member, @color_roles[color])
    Currency.change_balance(:deduct, member, 500)

    color_role =
      Api.get_guild_roles!(guild_id)
      |> Enum.find(&(&1.id == @color_roles[color]))

    "#{message.author.username} acquired #{color}!"
    |> (&Curie.embed(message, &1, color_role.color)).()
  end

  @impl true
  def command({"color", %{author: %{id: member}} = message, [color | _] = args}) do
    case get_color(color) do
      nil -> fallback("command", message, args)
      color -> confirm_transaction(color, member, message)
    end
  end

  @impl true
  def command(call), do: check_typo(call, @check_typo.command, &command/1)

  @impl true
  def subcommand({"remove", %{author: %{id: member}, guild_id: guild} = message, _args}) do
    if Currency.whitelisted?(message) do
      member_roles = Api.get_guild_member!(guild, member).roles
      color_roles = [@special_snowflake | Map.values(@color_roles)]

      for role <- member_roles do
        if role in color_roles, do: Api.remove_guild_member_role(guild, member, role)
      end

      Curie.embed(message, "Color associated roles were removed.", "green")
    end
  end

  @impl true
  def subcommand({"preview", message, [_ | [color | _]] = args}) do
    case get_color(color) do
      nil -> fallback("subcommand", message, args)
      color -> color_preview(color, message)
    end
  end

  @impl true
  def subcommand({_call, message, _args} = call) do
    unless check_typo(call, @check_typo.subcommand, &subcommand/1),
      do: Curie.embed(message, "Color not recognized.", "red")
  end
end
