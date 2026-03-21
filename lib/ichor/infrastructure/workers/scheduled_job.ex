defmodule Ichor.Infrastructure.Workers.ScheduledJob do
  @moduledoc "Oban worker that fires a scheduled job signal and handles one-time vs recurring."
  use Oban.Worker, queue: :scheduled, max_attempts: 3, unique: [period: 55, keys: [:job_id]]

  require Logger

  alias Ichor.Factory.CronJob
  alias Ichor.Infrastructure.CronSchedule

  @recurring_interval_ms 60_000

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"job_id" => job_id, "agent_id" => agent_id, "payload" => payload}
      }) do
    case CronJob.get(job_id) do
      {:ok, %{is_one_time: true} = job} ->
        case CronJob.complete(job) do
          {:ok, _} ->
            Ichor.Signals.emit(:scheduled_job, agent_id, %{agent_id: agent_id, payload: payload})
            :ok

          {:error, reason} ->
            Logger.warning("ScheduledJob: failed to complete #{job_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, job} ->
        next_fire_at = CronSchedule.next_recurrence(@recurring_interval_ms)

        case CronJob.reschedule(job, next_fire_at) do
          {:ok, _} ->
            Ichor.Signals.emit(:scheduled_job, agent_id, %{agent_id: agent_id, payload: payload})
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

          {:error, reason} ->
            Logger.warning("ScheduledJob: failed to reschedule #{job_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, _} ->
        :ok
    end
  end
end
