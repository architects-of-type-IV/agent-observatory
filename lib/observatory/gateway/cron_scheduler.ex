defmodule Observatory.Gateway.CronScheduler do
  @moduledoc """
  GenServer that manages scheduled one-time and recurring jobs.

  On startup, recovers all persisted `cron_jobs` rows and schedules timers.
  Jobs fire by broadcasting to `"agent:{agent_id}:scheduled"` via PubSub.
  One-time jobs are deleted after firing; recurring jobs reschedule.
  """

  use GenServer

  require Logger

  alias Observatory.Gateway.CronJob
  alias Observatory.Repo

  import Ecto.Query

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Schedules a one-time job for `agent_id` that fires after `delay_ms` milliseconds.

  Returns `:ok` on success or `{:error, :invalid_delay}` if `delay_ms` is not
  a positive integer.
  """
  def schedule_once(agent_id, delay_ms, payload) do
    GenServer.call(__MODULE__, {:schedule_once, agent_id, delay_ms, payload})
  end

  @doc "Returns all jobs for the given `agent_id`."
  def list_jobs(agent_id) do
    Repo.all(from(j in CronJob, where: j.agent_id == ^agent_id))
  end

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    try do
      jobs = Repo.all(CronJob)

      Enum.each(jobs, fn job ->
        delay = DateTime.diff(job.next_fire_at, DateTime.utc_now(), :millisecond)
        Process.send_after(self(), {:fire_job, job.id, job.agent_id, job.payload}, max(delay, 0))
      end)
    catch
      kind, reason ->
        Logger.debug("CronScheduler: skipping job recovery (#{kind}: #{inspect(reason)})")
    end

    {:ok, %{jobs: %{}}}
  end

  @impl true
  def handle_call({:schedule_once, _agent_id, delay_ms, _payload}, _from, state)
      when not is_integer(delay_ms) or delay_ms <= 0 do
    {:reply, {:error, :invalid_delay}, state}
  end

  def handle_call({:schedule_once, agent_id, delay_ms, payload}, _from, state) do
    next_fire_at =
      DateTime.utc_now()
      |> DateTime.add(delay_ms, :millisecond)
      |> DateTime.truncate(:second)

    attrs = %{
      agent_id: agent_id,
      payload: Jason.encode!(payload),
      next_fire_at: next_fire_at,
      is_one_time: true
    }

    changeset = CronJob.changeset(%CronJob{}, attrs)

    case Repo.insert(changeset) do
      {:ok, job} ->
        Process.send_after(self(), {:fire_job, job.id, job.agent_id, job.payload}, delay_ms)
        {:reply, :ok, state}

      {:error, changeset} ->
        Logger.warning("CronScheduler: failed to insert job: #{inspect(changeset.errors)}")
        {:reply, {:error, :insert_failed}, state}
    end
  end

  @impl true
  def handle_info({:fire_job, job_id, agent_id, payload_json}, state) do
    payload = Jason.decode!(payload_json)

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "agent:#{agent_id}:scheduled",
      {:scheduled_job, agent_id, payload}
    )

    try do
      case Repo.get(CronJob, job_id) do
        nil ->
          :ok

        %CronJob{is_one_time: true} = job ->
          Repo.delete(job)

        %CronJob{} = job ->
          next_fire_at =
            DateTime.utc_now()
            |> DateTime.add(60_000, :millisecond)
            |> DateTime.truncate(:second)

          job
          |> Ecto.Changeset.change(next_fire_at: next_fire_at)
          |> Repo.update()

          Process.send_after(self(), {:fire_job, job.id, job.agent_id, job.payload}, 60_000)
      end
    catch
      kind, reason ->
        Logger.debug("CronScheduler: DB error firing job #{job_id} (#{kind}: #{inspect(reason)})")
    end

    {:noreply, state}
  end
end
