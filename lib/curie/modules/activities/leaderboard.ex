defmodule Curie.Leaderboard do
  use Curie.Commands
  use GenServer

  alias Nostrum.Struct.Embed
  alias Nostrum.Cache.UserCache
  alias Nostrum.Api

  alias Curie.Data.{Balance, Leaderboard}
  alias Curie.Data

  import Nostrum.Struct.Embed

  @actions %{"◀" => :backward, "▶" => :forward, "🔄" => :refresh}
  @buttons ["◀", "▶", "🔄"]
  @check_typo ~w/lead/
  @self __MODULE__
  @page_length 5

  @type action :: :forward | :backward | :refresh | :new

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl true
  def init(_args) do
    state = recover_state()

    case Api.get_channel_message(state.channel_id, state.message_id) do
      {:ok, _message} ->
        {:ok, state}

      {:error, _reason} ->
        {:ok, %{id: state.id, channel_id: nil, message_id: nil}}
    end
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call({:update_and_get, new}, _from, state) do
    new_state = Map.merge(state, new)
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_cast({:update, new}, state), do: {:noreply, Map.merge(state, new)}

  @impl true
  def handle_cast(:save, state) do
    parameters = %{
      channel_id: state.channel_id,
      message_id: state.message_id,
      last_refresh: state.last_refresh,
      page_count: state.page_count,
      current_page: state.current_page,
      entries: state.entries
    }

    %Leaderboard{id: state.id}
    |> Leaderboard.changeset(parameters)
    |> Data.update()

    {:noreply, state}
  end

  @spec recover_state() :: Leaderboard.t()
  def recover_state, do: Data.one(Leaderboard)

  @spec create_new() :: map()
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

  @spec create_entries() :: [String.t()]
  def create_entries do
    Balance
    |> Data.all()
    |> Enum.group_by(& &1.value, & &1.member)
    |> Enum.into([])
    |> Enum.sort(&(&1 > &2))
    |> Enum.map(fn {value, list} -> {value, Enum.map(list, &UserCache.get!(&1).username)} end)
    |> Enum.map(&format_entry/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} -> "**#{index}.** taken by " <> entry end)
  end

  @spec format_entry({non_neg_integer(), [String.t()]}) :: String.t()
  def format_entry({value, list}) do
    {first, rest} = Enum.split(list, 3)
    members = Enum.join(first, ", ")
    overflow = if rest != [], do: ", + #{Enum.count(rest)}", else: ""
    "**#{members <> overflow}** with **#{value}**#{@tempest}"
  end

  @spec format_output(action()) :: Embed.t()
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

  @spec interaction(action()) :: no_return()
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

  @impl true
  def command({"lead", message, _args}) do
    state = GenServer.call(@self, :get)
    if state.message_id, do: Api.delete_all_reactions(state.channel_id, state.message_id)

    {:ok, %{id: message_id, channel_id: channel_id} = _message} =
      Curie.send(message, embed: format_output(:new))

    GenServer.cast(@self, {:update, %{channel_id: channel_id, message_id: message_id}})
    GenServer.cast(@self, :save)

    for button <- @buttons do
      Api.create_reaction!(channel_id, message_id, button)
      Process.sleep(300)
    end
  end

  @impl true
  def command(call), do: check_typo(call, @check_typo, &command/1)

  @spec handler(map()) :: no_return()
  def handler(%{heartbeat: _heartbeat} = message), do: super(message)

  def handler(%{emoji: emoji, message_id: message_id, user_id: user_id} = _reaction) do
    me = Nostrum.Cache.Me.get()
    lead_id = GenServer.call(@self, :get).message_id

    if me.id != user_id and message_id == lead_id and emoji.name in @buttons,
      do: interaction(@actions[emoji.name])
  end
end
