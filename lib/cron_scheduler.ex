defmodule CronScheduler do
  @moduledoc """
  Schedules one-off and recurring jobs over a pluggable store and queue.

  Extracted from a system where this was an Ash resource plus Oban. The logic
  worth keeping is not either of those — it is the split between them, and what
  happens at the seam.

  ## The two halves

  **The store** (`CronScheduler.Store`) is the source of truth for *what* is
  scheduled. **The queue** (`CronScheduler.Queue`) only knows *when* to wake
  something up. Neither is this library's business, so both are behaviours.

  That split is what makes `recover_jobs/0` possible: the queue may lose every
  timer it holds, and the schedule is still intact, because it lives in the
  store. On boot, walk the store and re-enqueue.

  ## Ordering at the seam

  Scheduling writes the store first, then the queue. If the queue rejects the
  job the store record is rolled back, so nothing is ever left scheduled with
  nothing due to wake it.

  Firing goes the other way: the store is updated first — one-time jobs deleted,
  recurring ones moved forward — and only then does the handler run. A crash in
  the handler therefore cannot leave a job re-firing in a loop. The trade is
  that the handler's own work is lost on a crash; if that matters, have the
  handler enqueue something durable rather than doing the work inline.

  ## Setup

      children = [
        CronScheduler.Store.ETS,
        CronScheduler.Queue.Timer
      ]

      config :cron_scheduler,
        store: CronScheduler.Store.ETS,
        queue: CronScheduler.Queue.Timer,
        handler: MyApp.JobHandler

  The bundled ETS store and timer queue are working implementations, but neither
  survives a restart — swap in a database store and a durable queue for
  production.

  ## Example

      CronScheduler.schedule_once("agent-1", 60_000, %{action: "health_check"})
      CronScheduler.schedule_recurring("agent-1", 300_000, %{action: "poll"})

      CronScheduler.list_jobs("agent-1")
      CronScheduler.recover_jobs()
  """

  require Logger

  alias CronScheduler.Job
  alias CronScheduler.Schedule

  @unique_period 120

  @doc """
  Schedule a one-time job to fire in `delay_ms`.

  `payload` may be any JSON-encodable term, or a string to pass through
  untouched. Returns `{:error, :invalid_delay}` for a non-positive delay and
  `{:error, :insert_failed}` if the store or queue refuses it.
  """
  @spec schedule_once(String.t(), pos_integer(), term()) ::
          {:ok, Job.t()} | {:error, :invalid_delay | :insert_failed}
  def schedule_once(agent_id, delay_ms, payload) do
    schedule(agent_id, delay_ms, payload, is_one_time: true)
  end

  @doc """
  Schedule a recurring job that fires every `interval_ms`.

  Each firing reschedules the next one, so the interval is honoured from the
  fire time rather than the original schedule time — a slow handler shifts the
  series rather than compressing it.
  """
  @spec schedule_recurring(String.t(), pos_integer(), term()) ::
          {:ok, Job.t()} | {:error, :invalid_delay | :insert_failed}
  def schedule_recurring(agent_id, interval_ms, payload) do
    schedule(agent_id, interval_ms, payload, is_one_time: false, interval_ms: interval_ms)
  end

  @doc "Every job scheduled for one agent."
  @spec list_jobs(String.t()) :: [Job.t()]
  def list_jobs(agent_id) do
    case store().for_agent(agent_id) do
      {:ok, jobs} -> jobs
      {:error, reason} -> warn("list_jobs failed for #{agent_id}", reason)
    end
  end

  @doc "Every scheduled job, soonest first."
  @spec list_all_jobs() :: [Job.t()]
  def list_all_jobs do
    case store().all_scheduled() do
      {:ok, jobs} -> jobs
      {:error, reason} -> warn("list_all_jobs failed", reason)
    end
  end

  @doc "Jobs already due as of `now`, soonest first."
  @spec due_jobs(DateTime.t()) :: [Job.t()]
  def due_jobs(now \\ DateTime.utc_now()) do
    case store().due(now) do
      {:ok, jobs} -> jobs
      {:error, reason} -> warn("due_jobs failed", reason)
    end
  end

  @doc "Cancel a scheduled job by id. Succeeds whether or not it existed."
  @spec cancel(String.t()) :: :ok | {:error, term()}
  def cancel(job_id) do
    case store().get(job_id) do
      {:ok, job} -> store().complete(job)
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Re-enqueue every job in the store.

  Call on boot. The queue is allowed to be forgetful — this is what makes that
  safe. Jobs whose time has already passed are enqueued with no delay, so
  downtime causes a late fire rather than a skipped one.

  Enqueues carry a unique period, so a queue that deduplicates will not create a
  second timer for a job that is already pending.
  """
  @spec recover_jobs() :: :ok
  def recover_jobs do
    Enum.each(list_all_jobs(), fn job ->
      delay_ms = Schedule.delay_until(job.next_fire_at)

      case enqueue(job, delay_ms) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "CronScheduler: failed to re-enqueue job #{job.id} for agent #{job.agent_id}: " <>
              inspect(reason)
          )
      end
    end)
  end

  @doc """
  Fire a job by id. Called by the queue when a job comes due.

  One-time jobs are completed and removed; recurring jobs are rescheduled and
  re-enqueued. The store is updated before the handler runs — see the module
  docs for why. An unknown id is a no-op, since a cancelled job may still have a
  timer in flight.
  """
  @spec fire(String.t()) :: :ok | {:error, term()}
  def fire(job_id) do
    case store().get(job_id) do
      {:ok, %Job{is_one_time: true} = job} -> fire_once(job)
      {:ok, job} -> fire_recurring(job)
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Encode a payload for storage.

  Strings pass through untouched; everything else is JSON-encoded, so the store
  only ever handles a string.
  """
  @spec encode_payload(term()) :: String.t()
  def encode_payload(payload) when is_binary(payload), do: payload
  def encode_payload(payload), do: JSON.encode!(payload)

  # Private

  defp schedule(agent_id, delay_ms, payload, job_opts) do
    with :ok <- Schedule.validate_delay(delay_ms) do
      job =
        Job.new(
          Keyword.merge(job_opts,
            agent_id: agent_id,
            payload: encode_payload(payload),
            next_fire_at: Schedule.next_fire_at(delay_ms)
          )
        )

      case store().insert(job) do
        {:ok, stored} -> enqueue_or_rollback(stored, delay_ms)
        {:error, reason} -> insert_failed("store rejected job for #{agent_id}", reason)
      end
    end
  end

  # The store accepted but the queue refused. Roll the record back rather than
  # leaving a job scheduled that nothing will ever wake.
  defp enqueue_or_rollback(job, delay_ms) do
    case enqueue(job, delay_ms) do
      :ok ->
        {:ok, job}

      {:error, reason} ->
        store().complete(job)
        insert_failed("queue rejected job #{job.id}", reason)
    end
  end

  defp insert_failed(message, reason) do
    Logger.warning("CronScheduler: #{message}: #{inspect(reason)}")
    {:error, :insert_failed}
  end

  defp enqueue(job, delay_ms) do
    queue().enqueue(job,
      schedule_in: Schedule.to_seconds(delay_ms),
      unique_period: @unique_period
    )
  end

  defp fire_once(job) do
    case store().complete(job) do
      :ok ->
        handle(job)

      {:error, reason} ->
        Logger.warning("CronScheduler: failed to complete #{job.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fire_recurring(job) do
    interval_ms = job.interval_ms || default_interval_ms()

    case store().reschedule(job, Schedule.next_fire_at(interval_ms)) do
      {:ok, rescheduled} ->
        handle(rescheduled)

        # A failed re-enqueue is survivable: the store already holds the next
        # fire time, so recover_jobs/0 picks it up on the next boot.
        case enqueue(rescheduled, interval_ms) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "CronScheduler: enqueue failed for #{job.id}: #{inspect(reason)}. " <>
                "Store is rescheduled; recover_jobs will re-enqueue on restart."
            )

            :ok
        end

      {:error, reason} ->
        Logger.warning("CronScheduler: failed to reschedule #{job.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle(job) do
    handler().handle_fire(job.agent_id, job.payload, job)
    :ok
  end

  defp warn(message, reason) do
    Logger.warning("CronScheduler: #{message}: #{inspect(reason)}")
    []
  end

  defp store, do: fetch(:store)
  defp queue, do: fetch(:queue)
  defp handler, do: Application.get_env(:cron_scheduler, :handler, CronScheduler.Handler.Noop)

  defp default_interval_ms,
    do: Application.get_env(:cron_scheduler, :default_interval_ms, 60_000)

  defp fetch(key) do
    Application.get_env(:cron_scheduler, key) ||
      raise ArgumentError, """
      CronScheduler needs a #{key}. Set it with:

          config :cron_scheduler, #{key}: MyApp.#{key |> to_string() |> String.capitalize()}

      For development, the bundled implementations are
      `CronScheduler.Store.ETS` and `CronScheduler.Queue.Timer`.
      """
  end
end
