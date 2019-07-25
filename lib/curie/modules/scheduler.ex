defmodule Curie.Scheduler do
  use GenServer

  alias Curie.Scheduler.Tasks
  alias Crontab.CronExpression
  alias Crontab.Scheduler

  @spec start_link(any) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  @spec init(any) :: {:ok, nil, {:continue, :schedule_tasks}}
  def init(_args) do
    {:ok, nil, {:continue, :schedule_tasks}}
  end

  @impl GenServer
  @spec handle_continue(:schedule_tasks, any) :: {:noreply, any}
  def handle_continue(:schedule_tasks, state) do
    Enum.each(Tasks.get(), &schedule_tasks/1)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:run_tasks, {_run_time, work} = batch}, state) do
    cond do
      is_list(work) -> Enum.each(work, &Task.start/1)
      is_function(work) -> Task.start(work)
    end

    schedule_tasks(batch)
    {:noreply, state}
  end

  @spec schedule_tasks({CronExpression.t(), [function] | function}) :: reference
  def schedule_tasks({run_time, _work} = batch) do
    naive_current_time = NaiveDateTime.from_erl!(:calendar.local_time())

    wait_amount =
      Scheduler.get_next_run_dates(run_time, naive_current_time)
      |> Enum.take(2)
      |> case do
        [first, _next] when first != naive_current_time -> first
        [_first, next] when next != naive_current_time -> next
      end
      |> NaiveDateTime.diff(naive_current_time, :millisecond)

    Process.send_after(self(), {:run_tasks, batch}, wait_amount)
  end
end
