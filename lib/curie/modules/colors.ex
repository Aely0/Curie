defmodule Curie.Colors do
  alias Nostrum.Api

  @special_snowflake 371_732_667_080_638_466
  @colors Application.get_env(:curie, :color_roles)

  def get_color(color) do
    color
    |> String.downcase()
    |> String.capitalize()
    |> (&if(&1 in Map.keys(@colors), do: &1, else: nil)).()
  end

  def command({"color", %{author: %{id: member}} = message, words}) when length(words) >= 2 do
    case words |> Enum.at(1) |> get_color() do
      nil ->
        with {:ok, match} <- Curie.check_typo(Enum.at(words, 1), Map.keys(@colors)) do
          List.replace_at(words, 1, match)
          |> (&command({"color", message, &1})).()
        else
          _no_match ->
            subcommand({Enum.at(words, 1), message, words})
        end

      color ->
        cond do
          !Curie.Currency.whitelisted?(message) ->
            nil

          Curie.Currency.get_balance(member) < 500 ->
            Curie.embed(message, "Insufficient balance.", "red")

          true ->
            member_roles = Api.get_guild_member!(message.guild_id, member).roles
            color_roles = Map.values(@colors)

            for role <- member_roles do
              if role in color_roles,
                do: Api.remove_guild_member_role(message.guild_id, member, role)
            end

            if @special_snowflake not in member_roles,
              do: Api.add_guild_member_role(message.guild_id, member, @special_snowflake)

            Api.add_guild_member_role(message.guild_id, member, @colors[color])

            Curie.Currency.change_balance(:deduct, member, 500)

            color_role =
              Api.get_guild_roles!(message.guild_id)
              |> Enum.find(&(&1.id == @colors[color]))

            "#{message.author.username} acquired #{color}!"
            |> (&Curie.embed(message, &1, color_role.color)).()
        end
    end
  end

  def command({call, message, words}) do
    with {:ok, match} <- Curie.check_typo(call, "color"), do: command({match, message, words})
  end

  def subcommand({"remove", message, words}) when length(words) >= 2 do
    if Curie.Currency.whitelisted?(message) do
      member_roles = Api.get_guild_member!(message.guild_id, message.author.id).roles
      color_roles = [@special_snowflake | Map.values(@colors)]

      for role <- member_roles do
        if role in color_roles,
          do: Api.remove_guild_member_role(message.guild_id, message.author.id, role)
      end

      Curie.embed(message, "Color associated roles were removed.", "green")
    end
  end

  def subcommand({"preview", message, words}) when length(words) >= 3 do
    case words |> Enum.at(2) |> get_color() do
      nil ->
        with {:ok, match} <- Curie.check_typo(Enum.at(words, 2), Map.keys(@colors)) do
          List.replace_at(words, 2, match)
          |> (&subcommand({"preview", message, &1})).()
        else
          _no_match ->
            Curie.embed(message, "Color not recognized.", "red")
        end

      color ->
        me = Nostrum.Cache.Me.get().id

        color_role =
          Api.get_guild_roles!(message.guild_id)
          |> Enum.find(&(&1.id == @colors[color]))

        Api.add_guild_member_role(message.guild_id, me, @colors[color])

        Curie.embed(message, color, color_role.color)

        Api.remove_guild_member_role(message.guild_id, me, @colors[color])
    end
  end

  def subcommand({call, message, words}) do
    registered = ["remove", "preview"]

    with {:ok, match} <- Curie.check_typo(call, registered) do
      subcommand({match, message, words})
    else
      _unknown_command_or_color ->
        Curie.embed(message, "Color not recognized.", "red")
    end
  end

  def handler(message), do: if(Curie.command?(message), do: message |> Curie.parse() |> command())
end
