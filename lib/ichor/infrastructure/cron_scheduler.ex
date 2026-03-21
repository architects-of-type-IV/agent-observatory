defmodule Ichor.Infrastructure.CronScheduler do
  @moduledoc """
  GenServer that manages scheduled one-time and recurring jobs.

  On startup, recovers all persisted `cron_jobs` rows and schedules timers.
  Jobs fire by emitting a `:scheduled_job` signal for `agent_id`.
  One-time jobs are completed (destroyed) after firing; recurring jobs reschedule.

  Schedule math is delegated to `CronSchedule`.
  """

  use GenServer

  require Logger

  alias Ichor.Infrastructure.CronJob
  alias Ichor.Infrastructure.CronSchedule

  @recurring_interval_ms 60_000

  @doc "Start the CronScheduler GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Schedules a one-time job for `agent_id` that fires after `delay_ms` milliseconds.

  Returns `:ok` on success or `{:error, :invalid_delay}` if `delay_ms` is not
  a positive integer.
  """
  @spec schedule_once(String.t(), pos_integer(), term()) :: :ok | {:error, :invalid_delay}
  def schedule_once(agent_id, delay_ms, payload) do
    GenServer.call(__MODULE__, {:schedule_once, agent_id, delay_ms, payload})
  end

  @doc "Returns all jobs for the given `agent_id`."
  @spec list_jobs(String.t()) :: [Ichor.Infrastructure.CronJob.t()]
  def list_jobs(agent_id), do: CronJob.for_agent!(agent_id)

  @doc "Returns all scheduled jobs across all agents."
  @spec list_all_jobs() :: [Ichor.Infrastructure.CronJob.t()]
  def list_all_jobs do
    CronJob.all_scheduled!()
  rescue
    _ -> []
  end

  @impl true
  def init(_opts) do
    try do
      Enum.each(list_all_jobs(), fn job ->
        delay = CronSchedule.delay_until(job.next_fire_at)
        Process.send_after(self(), {:fire_job, job.id, job.agent_id, job.payload}, delay)
      end)
    catch
      kind, reason ->
        Logger.debug("CronScheduler: skipping job recovery (#{kind}: #{inspect(reason)})")
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call({:schedule_once, agent_id, delay_ms, payload}, _from, state) do
    with :ok <- CronSchedule.validate_delay(delay_ms) do
      next_fire_at = CronSchedule.next_fire_at(delay_ms)
      encoded = Jason.encode!(payload)

      case CronJob.schedule_once(agent_id, encoded, next_fire_at) do
        {:ok, job} ->
          Process.send_after(self(), {:fire_job, job.id, job.agent_id, job.payload}, delay_ms)
          {:reply, :ok, state}

        {:error, reason} ->
          Logger.warning("CronScheduler: failed to insert job: #{inspect(reason)}")
          {:reply, {:error, :insert_failed}, state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:fire_job, job_id, agent_id, payload_json}, state) do
    payload = Jason.decode!(payload_json)

    Ichor.Signals.emit(:scheduled_job, agent_id, %{agent_id: agent_id, payload: payload})

    try do
      case CronJob.get(job_id) do
        {:ok, %{is_one_time: true} = job} ->
          CronJob.complete(job)

        {:ok, job} ->
          next_fire_at = CronSchedule.next_recurrence(@recurring_interval_ms)

          case CronJob.reschedule(job, next_fire_at) do
            {:ok, _} ->
              Process.send_after(
                self(),
                {:fire_job, job.id, job.agent_id, job.payload},
                @recurring_interval_ms
              )

            {:error, reason} ->
              Logger.warning(
                "CronScheduler: failed to reschedule job #{job_id}: #{inspect(reason)}"
              )
          end

        {:error, _} ->
          :ok
      end
    catch
      kind, reason ->
        Logger.debug("CronScheduler: DB error firing job #{job_id} (#{kind}: #{inspect(reason)})")
    end

    {:noreply, state}
  end
end
