defmodule Curie.Weather do
  use Curie.Commands

  import Nostrum.Struct.Embed

  alias Nostrum.Struct.{Channel, Embed}
  alias Nostrum.Api

  @check_typo ~w/weather/

  @spec google_url([String.t()]) :: String.t()
  def google_url(location) do
    if(location == [], do: "Rīga", else: Enum.join(location, "+"))
    |> (&("https://maps.googleapis.com/maps/api/geocode/json?key=" <>
            Application.get_env(:curie, :googlemaps) <> "&address=" <> &1)).()
  end

  @spec darkskies_url(%{String.t() => float(), String.t() => float()}) :: String.t()
  def darkskies_url(%{"lat" => lat, "lng" => lng}) do
    "https://api.darksky.net/forecast/" <>
      Application.get_env(:curie, :darkskies) <>
      "/#{lat},#{lng}?units=si&exclude=minutely,hourly,daily,alerts,flags"
  end

  @spec get_location(map(), Channel.id()) :: {:ok, {map(), String.t()}} | {:error, String.t()}
  def get_location(response, channel) when is_map(response) do
    case response do
      %{"status" => "OK", "results" => [first | _rest]} ->
        {:ok, {first["geometry"]["location"], first["formatted_address"]}}

      %{"status" => "ZERO_RESULTS"} ->
        Curie.embed!(channel, "Location not found.", "red")
        {:error, "Location not found."}
    end
  end

  @spec get_location([String.t()], Channel.id()) ::
          {:ok, {map(), String.t()}} | {:error, String.t()}
  def get_location(location, channel) when is_list(location) do
    case Curie.get(google_url(location)) do
      {:ok, %{body: body}} ->
        body |> Poison.decode!() |> get_location(channel)

      {:error, reason} = error ->
        Curie.embed!(channel, "Unable to retrieve location. (#{reason})", "red")
        error
    end
  end

  @spec get_local_time(String.t()) :: String.t()
  def get_local_time(timezone) do
    timezone |> Timex.now() |> Timex.format!("%H:%M, %B %d", :strftime)
  end

  @spec format_forecast(%{String.t() => map(), String.t() => String.t()}, String.t()) ::
          String.t()
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

  @spec create_embed(String.t()) :: Embed.t()
  def create_embed(description) do
    %Nostrum.Struct.Embed{}
    |> put_author("Current weather", nil, "https://i.imgur.com/dykOoMW.png")
    |> put_timestamp(Timex.now() |> DateTime.to_iso8601())
    |> put_color(Curie.color("green"))
    |> put_description(description)
  end

  @spec get_forecast({map(), String.t()}, Channel.id()) ::
          {:ok, String.t()} | {:error, String.t()}
  def get_forecast({coords, address}, channel) do
    case Curie.get(darkskies_url(coords)) do
      {:ok, %{body: body}} ->
        forecast = body |> Poison.decode!() |> format_forecast(address)
        {:ok, forecast}

      {:error, reason} = error ->
        Curie.embed!(channel, "Unable to retrieve forecast. (#{reason})", "red")
        error
    end
  end

  @impl Curie.Commands
  def command({"weather", %{channel_id: channel}, location}) do
    Api.start_typing(channel)

    with {:ok, location} <- get_location(location, channel),
         {:ok, forecast} <- get_forecast(location, channel) do
      Curie.send(channel, embed: create_embed(forecast))
    end
  end

  @impl Curie.Commands
  def command(call) do
    check_typo(call, @check_typo, &command/1)
  end
end
