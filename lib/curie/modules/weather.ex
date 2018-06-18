defmodule Curie.Weather do
  alias Nostrum.Api

  import Nostrum.Struct.Embed

  def google_url(location) do
    if(Enum.empty?(location), do: "Rīga", else: Enum.join(location, "+"))
    |> (&("https://maps.googleapis.com/maps/api/geocode/json?key=" <>
            Application.get_env(:curie, :googlemaps) <> "&address=" <> &1)).()
  end

  def darkskies_url(%{"lat" => lat, "lng" => lng}) do
    "https://api.darksky.net/forecast/" <>
      Application.get_env(:curie, :darkskies) <>
      "/#{lat},#{lng}?units=si&exclude=minutely,hourly,daily,alerts,flags"
  end

  def get_location(response, channel) when is_map(response) do
    case response do
      %{"status" => "OK", "results" => [first | _rest]} ->
        {first["geometry"]["location"], first["formatted_address"]}

      %{"status" => "ZERO_RESULTS"} ->
        Curie.embed!(channel, "Location not found.", "red")
    end
  end

  def get_location(location, channel) when is_list(location) do
    case Curie.get(google_url(location)) do
      {200, response} ->
        response.body |> Poison.decode!() |> get_location(channel)

      {:failed, reason} ->
        Curie.embed!(channel, "Unable to retrieve location. (#{reason})", "red")
    end
  end

  def get_local_time(timezone),
    do: timezone |> Timex.now() |> Timex.format!("%H:%M, %B %d", :strftime)

  def format_forecast(%{"currently" => weather, "timezone" => timezone}, address) do
    "Location: #{address}\n" <>
      "Local time: #{get_local_time(timezone)}\n" <>
      "Weather: #{weather["summary"]}\n" <>
      "Temperature: #{weather["temperature"]}°C\n" <>
      "Apparent: #{weather["apparentTemperature"]}°C\n" <>
      "Wind speed: #{weather["windSpeed"]}m/s\n" <>
      "Wind direction: #{weather["windBearing"]}°\n" <>
      "Humidity: #{trunc(weather["humidity"] * 100)}%\n" <>
      "Cloud coverage: #{trunc(weather["cloudCover"] * 100)}%"
  end

  def create_embed(description) do
    %Nostrum.Struct.Embed{}
    |> put_author("Current weather", nil, "https://i.imgur.com/dykOoMW.png")
    |> put_timestamp(Timex.now() |> DateTime.to_iso8601())
    |> put_color(Curie.color("green"))
    |> put_description(description)
  end

  def get_forecast({coords, address}, channel) do
    case Curie.get(darkskies_url(coords)) do
      {200, response} ->
        response.body |> Poison.decode!() |> format_forecast(address)

      {:failed, reason} ->
        Curie.embed!(channel, "Unable to retrieve forecast. (#{reason})", "red")
    end
  end

  def command({"weather", %{channel_id: channel} = message, [_call | location]}) do
    Api.start_typing(message.channel_id)

    with location when is_tuple(location) <- get_location(location, channel),
         forecast when is_binary(forecast) <- get_forecast(location, channel),
         do: Curie.send(channel, embed: create_embed(forecast))
  end

  def command({call, message, words}) do
    with {:ok, match} <- Curie.check_typo(call, "weather"), do: command({match, message, words})
  end

  def handler(message), do: if(Curie.command?(message), do: message |> Curie.parse() |> command())
end
