defmodule CronScheduler.Queue.Timer do
  @moduledoc """
  In-process `CronScheduler.Queue` built on `Process.send_after/3`.

  A working reference implementation, and enough on its own for a single node
  that can tolerate losing timers on restart — `CronScheduler.recover_jobs/0`
  rebuilds them from the store.

  Deduplication is real: a second enqueue of the same job id within its
  `:unique_period` is dropped rather than producing a duplicate timer, which is
  what stops recovery from double-firing jobs that were already pending.

  Add it to your supervision tree:

      children = [CronScheduler.Queue.Timer]

      config :cron_scheduler, queue: CronScheduler.Queue.Timer
  """

  use GenServer

  require Logger

  @behaviour CronScheduler.Queue

  alias CronScheduler.Job

  @doc "Start the timer process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Job ids with a timer currently pending."
  @spec pending() :: [String.t()]
  def pending, do: GenServer.call(__MODULE__, :pending)

  @doc "Cancel every pending timer. Test helper."
  @spec clear() :: :ok
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl CronScheduler.Queue
  def enqueue(%Job{} = job, opts \\ []) do
    GenServer.call(__MODULE__, {:enqueue, job, opts})
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{timers: %{}, enqueued_at: %{}}}

  @impl GenServer
  def handle_call({:enqueue, job, opts}, _from, state) do
    if duplicate?(state, job.id, Keyword.get(opts, :unique_period, 0)) do
      {:reply, :ok, state}
    else
      delay_ms = Keyword.get(opts, :schedule_in, 0) * 1000
      ref = Process.send_after(self(), {:fire, job.id}, delay_ms)

      state = %{
        state
        | timers: Map.put(state.timers, job.id, ref),
          enqueued_at: Map.put(state.enqueued_at, job.id, now_ms())
      }

      {:reply, :ok, state}
    end
  end

  def handle_call(:pending, _from, state), do: {:reply, Map.keys(state.timers), state}

  def handle_call(:clear, _from, state) do
    Enum.each(state.timers, fn {_id, ref} -> Process.cancel_timer(ref) end)
    {:reply, :ok, %{state | timers: %{}, enqueued_at: %{}}}
  end

  @impl GenServer
  def handle_info({:fire, job_id}, state) do
    # Fire in a task: a slow or crashing handler must not stall the timers for
    # every other job.
    Task.start(fn -> safe_fire(job_id) end)

    {:noreply, %{state | timers: Map.delete(state.timers, job_id)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp safe_fire(job_id) do
    CronScheduler.fire(job_id)
  rescue
    error -> Logger.warning("CronScheduler.Queue.Timer: job #{job_id} raised #{inspect(error)}")
  end

  defp duplicate?(_state, _job_id, period) when period <= 0, do: false

  defp duplicate?(state, job_id, period) do
    case Map.get(state.enqueued_at, job_id) do
      nil -> false
      at -> now_ms() - at < period * 1000
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
