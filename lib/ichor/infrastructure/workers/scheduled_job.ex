defmodule Ichor.Infrastructure.Workers.ScheduledJob do
  @moduledoc "Oban worker that fires a scheduled job signal and handles one-time vs recurring."
  use Oban.Worker, queue: :scheduled, max_attempts: 3

  require Logger

  alias Ichor.Infrastructure.{CronJob, CronSchedule}

  @recurring_interval_ms 60_000

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"job_id" => job_id, "agent_id" => agent_id, "payload" => payload}
      }) do
    Ichor.Signals.emit(:scheduled_job, agent_id, %{agent_id: agent_id, payload: payload})

    case CronJob.get(job_id) do
      {:ok, %{is_one_time: true} = job} ->
        CronJob.complete(job)
        :ok

      {:ok, job} ->
        next_fire_at = CronSchedule.next_recurrence(@recurring_interval_ms)

        case CronJob.reschedule(job, next_fire_at) do
          {:ok, _} ->
            delay_seconds = div(@recurring_interval_ms, 1000)

            %{"job_id" => job_id, "agent_id" => agent_id, "payload" => payload}
            |> __MODULE__.new(schedule_in: delay_seconds)
            |> Oban.insert()

            :ok

          {:error, reason} ->
            Logger.warning("ScheduledJob: failed to reschedule #{job_id}: #{inspect(reason)}")
            :ok
        end

      {:error, _} ->
        :ok
    end
  end
end
