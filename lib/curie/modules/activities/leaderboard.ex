defmodule Curie.Leaderboard do
  use GenServer

  alias Nostrum.Cache.UserCache
  alias Nostrum.Api

  import Nostrum.Struct.Embed

  @actions %{"◀" => :backward, "▶" => :forward, "🔄" => :refresh}
  @buttons ["◀", "▶", "🔄"]
  @self __MODULE__
  @page_length 5

  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  def init(_args) do
    state = recover_state()

    case Api.get_channel_message(state.channel_id, state.message_id) do
      {:ok, _message} ->
        {:ok, state}

      {:error, _reason} ->
        {:ok, %{channel_id: nil, message_id: nil}}
    end
  end

  def handle_call(:get, _from, state), do: {:reply, state, state}

  def handle_call({:update_and_get, new}, _from, state) do
    new_state = Map.merge(state, new)
    {:reply, new_state, new_state}
  end

  def handle_cast({:update, new}, state), do: {:noreply, Map.merge(state, new)}

  def handle_cast(:save, state) do
    query =
      "UPDATE leaderboard SET channel_id=$1, message_id=$2, last_refresh=$3, " <>
        "page_count=$4, current_page=$5, entries=$6"

    parameters = [
      state.channel_id,
      state.message_id,
      state.last_refresh,
      state.page_count,
      state.current_page,
      state.entries |> parse_entries()
    ]

    Postgrex.query!(Postgrex, query, parameters)

    {:noreply, state}
  end

  def parse_entries(entries) when is_list(entries), do: Enum.join(entries, "<&&>")
  def parse_entries(entries) when is_binary(entries), do: String.split(entries, "<&&>")

  def recover_state do
    Postgrex.query!(Postgrex, "SELECT * FROM leaderboard", [])
    |> (&Enum.zip(&1.columns, &1.rows |> hd)).()
    |> Enum.filter(&(!match?({"id", _id}, &1)))
    |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)
    |> Enum.into(%{})
    |> (&%{&1 | entries: parse_entries(&1.entries)}).()
  end

  def create_new do
    entries = create_entries()

    state = %{
      last_refresh: Timex.now() |> DateTime.to_iso8601(),
      page_count: Float.ceil(length(entries) / @page_length) |> trunc(),
      current_page: 1,
      entries: entries
    }

    GenServer.call(@self, {:update_and_get, state})
  end

  def create_entries do
    overflow = fn list -> if length(list) > 3, do: ", + #{length(list) - 3}", else: "" end
    format = fn list -> Enum.slice(list, 0..2) |> Enum.join(", ") end

    Postgrex.query!(Postgrex, "SELECT member, value FROM balance", []).rows
    |> Enum.group_by(&Enum.at(&1, 1), &Enum.at(&1, 0))
    |> Enum.into([])
    |> Enum.sort(&(&1 > &2))
    |> Enum.map(fn {value, list} -> {value, list |> Enum.map(&UserCache.get!(&1).username)} end)
    |> Enum.map(fn {value, list} ->
      "**#{format.(list)}#{overflow.(list)}** with **#{value}**#{Curie.tempest()}"
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} -> "**#{index}.** taken by " <> entry end)
  end

  def format_output(action) do
    state =
      if action in [:new, :refresh],
        do: create_new(),
        else: GenServer.call(@self, :get)

    section_start = @page_length * state.current_page - @page_length

    section_end =
      if action == :forward and state.current_page == state.page_count,
        do: length(state.entries),
        else: @page_length * state.current_page - 1

    ranks = state.entries |> Enum.slice(section_start..section_end) |> Enum.join("\n")

    %Nostrum.Struct.Embed{}
    |> put_color(Curie.color("lblue"))
    |> put_description("Tempest rankings:\n#{ranks}")
    |> put_footer("Page #{state.current_page}/#{state.page_count}", nil)
    |> put_timestamp(state.last_refresh)
  end

  def interaction(:backward) do
    state = GenServer.call(@self, :get)

    if state.current_page > 1 do
      GenServer.cast(@self, {:update, %{current_page: state.current_page - 1}})
      Curie.edit!(state.channel_id, state.message_id, embed: format_output(:backward))
      GenServer.cast(@self, :save)
    end
  end

  def interaction(:forward) do
    state = GenServer.call(@self, :get)

    if state.current_page < state.page_count do
      GenServer.cast(@self, {:update, %{current_page: state.current_page + 1}})
      Curie.edit!(state.channel_id, state.message_id, embed: format_output(:forward))
      GenServer.cast(@self, :save)
    end
  end

  def interaction(:refresh) do
    state = GenServer.call(@self, :get)
    Curie.edit!(state.channel_id, state.message_id, embed: format_output(:refresh))
    GenServer.cast(@self, :save)
  end

  def command({"lead", message, _words}) do
    state = GenServer.call(@self, :get)
    if state.message_id, do: Api.delete_all_reactions(state.channel_id, state.message_id)
    {:ok, message} = Curie.send(message.channel_id, embed: format_output(:new))
    GenServer.cast(@self, {:update, %{channel_id: message.channel_id, message_id: message.id}})
    GenServer.cast(@self, :save)
    for button <- @buttons do
      Api.create_reaction!(message.channel_id, message.id, button)
      Process.sleep(300)
    end
  end

  def command({call, message, words}) do
    with {:ok, match} <- Curie.check_typo(call, "lead"), do: command({match, message, words})
  end

  def handler(%{heartbeat: _heartbeat} = message) do
    if(Curie.command?(message), do: message |> Curie.parse() |> command())
  end

  def handler(%{emoji: emoji, message_id: message_id, user_id: user_id} = _reaction) do
    me = Nostrum.Cache.Me.get()
    lead_id = GenServer.call(@self, :get).message_id
    if me.id != user_id and message_id == lead_id and emoji.name in @buttons,
      do: interaction(@actions[emoji.name])
  end
end
