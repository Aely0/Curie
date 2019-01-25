defmodule Curie.Leaderboard do
  use Curie.Commands
  use GenServer

  import Nostrum.Struct.Embed

  alias Nostrum.Struct.Embed
  alias Nostrum.Api

  alias Curie.Data.{Balance, Leaderboard}
  alias Curie.Data

  @type action :: :forward | :backward | :refresh | :new

  @self __MODULE__

  @actions %{"◀" => :backward, "▶" => :forward, "🔄" => :refresh}
  @buttons ["◀", "▶", "🔄"]
  @check_typo ~w/lead/
  @page_length 5

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl true
  def init(_args) do
    with %Leaderboard{channel_id: channel_id, message_id: message_id} = state
         when channel_id != nil and message_id != nil <- load_state(),
         {:ok, _message} <- Api.get_channel_message(channel_id, message_id) do
      {:ok, state}
    else
      _no_recoverable_state -> {:ok, %{channel_id: nil, guild_id: nil, message_id: nil}}
    end
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:update_and_get, new}, _from, state) do
    new_state = Map.merge(state, new)
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_cast({:update, new}, state) do
    {:noreply, Map.merge(state, new)}
  end

  @impl true
  def handle_cast(:save, state) do
    parameters = %{
      channel_id: state.channel_id,
      guild_id: state.guild_id,
      message_id: state.message_id,
      last_refresh: state.last_refresh,
      page_count: state.page_count,
      current_page: state.current_page,
      entries: state.entries
    }

    Leaderboard
    |> Data.one()
    |> Leaderboard.changeset(parameters)
    |> Data.insert_or_update()

    {:noreply, state}
  end

  @spec get_state() :: Leaderboard.t()
  def get_state do
    GenServer.call(@self, :get)
  end

  @spec update_and_get_state(map()) :: Leaderboard.t()
  def update_and_get_state(new_state) do
    GenServer.call(@self, {:update_and_get, new_state})
  end

  @spec update_state(map()) :: no_return()
  def update_state(new_state) do
    GenServer.cast(@self, {:update, new_state})
  end

  @spec save_state() :: no_return()
  def save_state do
    GenServer.cast(@self, :save)
  end

  @spec load_state() :: Leaderboard.t()
  def load_state do
    Data.one(Leaderboard)
  end

  @spec create_new() :: Leaderboard.t()
  def create_new do
    entries = create_entries()

    state = %{
      last_refresh: Timex.now() |> DateTime.to_iso8601(),
      page_count: Float.ceil(length(entries) / @page_length) |> trunc(),
      current_page: 1,
      entries: entries
    }

    update_and_get_state(state)
  end

  @spec create_entries() :: [String.t()]
  def create_entries do
    %{guild_id: guild_id} = get_state()

    Balance
    |> Data.all()
    |> Enum.group_by(& &1.value, & &1.member)
    |> Enum.into([])
    |> Enum.sort(&(&1 > &2))
    |> Enum.map(fn {value, list} ->
      {value, Enum.map(list, &Curie.get_display_name(guild_id, &1))}
    end)
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
    %{
      current_page: current_page,
      page_count: page_count,
      entries: entries,
      last_refresh: last_refresh
    } =
      if action in [:new, :refresh],
        do: create_new(),
        else: get_state()

    section_start = @page_length * current_page - @page_length

    section_end =
      if action == :forward and current_page == page_count,
        do: length(entries),
        else: @page_length * current_page - 1

    ranks = entries |> Enum.slice(section_start..section_end) |> Enum.join("\n")

    %Nostrum.Struct.Embed{}
    |> put_color(Curie.color("lblue"))
    |> put_description("Tempest rankings:\n#{ranks}")
    |> put_footer("Page #{current_page}/#{page_count}", nil)
    |> put_timestamp(last_refresh)
  end

  @spec interaction(action()) :: no_return()
  def interaction(:backward) do
    state = get_state()

    if state.current_page > 1 do
      update_state(%{current_page: state.current_page - 1})
      Curie.edit!(state.channel_id, state.message_id, embed: format_output(:backward))
      save_state()
    end
  end

  def interaction(:forward) do
    state = get_state()

    if state.current_page < state.page_count do
      update_state(%{current_page: state.current_page + 1})
      Curie.edit!(state.channel_id, state.message_id, embed: format_output(:forward))
      save_state()
    end
  end

  def interaction(:refresh) do
    state = get_state()
    Curie.edit!(state.channel_id, state.message_id, embed: format_output(:refresh))
    save_state()
  end

  @impl true
  def command({"lead", %{guild_id: guild_id} = message, _args}) do
    %{message_id: old_message_id, channel_id: old_channel_id} =
      update_and_get_state(%{guild_id: guild_id})

    if old_message_id do
      Api.delete_all_reactions(old_channel_id, old_message_id)
    end

    {:ok, %{id: message_id, channel_id: channel_id}} =
      Curie.send(message, embed: format_output(:new))

    update_state(%{channel_id: channel_id, message_id: message_id})
    save_state()

    for button <- @buttons do
      Api.create_reaction!(channel_id, message_id, button)
      Process.sleep(300)
    end
  end

  @impl true
  def command(call) do
    check_typo(call, @check_typo, &command/1)
  end

  @spec handler(map()) :: no_return()
  def handler(%{emoji: %{name: emoji}, message_id: message_id, user_id: user_id}) do
    lead_id = get_state().message_id

    if Curie.my_id() != user_id and message_id == lead_id and emoji in @buttons do
      interaction(@actions[emoji])
    end
  end

  def handler(%{guild_id: guild_id} = message) do
    if guild_id do
      super(message)
    end
  end
end
