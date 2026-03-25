defmodule Ichor.Infrastructure.Workers.ScheduledJob do
  @moduledoc "Oban worker that fires a scheduled job signal and handles one-time vs recurring."
  use Oban.Worker, queue: :scheduled, max_attempts: 3, unique: [period: 55, keys: [:job_id]]

  require Logger

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Factory.CronJob

  @recurring_interval_ms 60_000

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"job_id" => job_id, "agent_id" => agent_id, "payload" => payload}
      }) do
    case CronJob.get(job_id) do
      {:ok, %{is_one_time: true} = job} -> perform_one_time(job, job_id, agent_id, payload)
      {:ok, job} -> perform_recurring(job, job_id, agent_id, payload)
      {:error, _} -> :ok
    end
  end

  defp perform_one_time(job, job_id, agent_id, payload) do
    case CronJob.complete(job) do
      :ok ->
        Events.emit(
          Event.new(
            "agent.scheduled_job",
            agent_id,
            %{agent_id: agent_id, payload: payload, scope_id: agent_id}
          )
        )

        :ok

      {:error, reason} ->
        Logger.warning("ScheduledJob: failed to complete #{job_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp next_recurrence(interval_ms) do
    DateTime.utc_now()
    |> DateTime.add(interval_ms, :millisecond)
    |> DateTime.truncate(:second)
  end

  defp perform_recurring(job, job_id, agent_id, payload) do
    next_fire_at = next_recurrence(@recurring_interval_ms)

    case CronJob.reschedule(job, next_fire_at) do
      {:ok, _} ->
        Events.emit(
          Event.new(
            "agent.scheduled_job",
            agent_id,
            %{agent_id: agent_id, payload: payload, scope_id: agent_id}
          )
        )

        enqueue_next_recurring(job_id, agent_id, payload)

      {:error, reason} ->
        Logger.warning("ScheduledJob: failed to reschedule #{job_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp enqueue_next_recurring(job_id, agent_id, payload) do
    delay_seconds = div(@recurring_interval_ms, 1000)

    case %{"job_id" => job_id, "agent_id" => agent_id, "payload" => payload}
         |> __MODULE__.new(schedule_in: delay_seconds)
         |> Oban.insert() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "ScheduledJob: Oban insert failed for #{job_id}: #{inspect(reason)}. " <>
            "DB rescheduled; recover_jobs will re-enqueue on restart."
        )

        :ok
    end
  end
end
