defmodule Ichor.Infrastructure.CronScheduler do
  @moduledoc "Schedules jobs via Oban. No longer a GenServer."

  alias Ichor.Infrastructure.{CronJob, CronSchedule}
  alias Ichor.Infrastructure.Workers.ScheduledJob

  @doc """
  Schedules a one-time job for `agent_id` that fires after `delay_ms` milliseconds.

  Returns `:ok` on success or `{:error, :invalid_delay}` if `delay_ms` is not
  a positive integer.
  """
  @spec schedule_once(String.t(), pos_integer(), term()) ::
          :ok | {:error, :invalid_delay | :insert_failed}
  def schedule_once(agent_id, delay_ms, payload) do
    with :ok <- CronSchedule.validate_delay(delay_ms) do
      next_fire_at = CronSchedule.next_fire_at(delay_ms)
      encoded = Jason.encode!(payload)

      case CronJob.schedule_once(agent_id, encoded, next_fire_at) do
        {:ok, job} ->
          delay_seconds = div(delay_ms, 1000)

          case %{"job_id" => job.id, "agent_id" => agent_id, "payload" => encoded}
               |> ScheduledJob.new(
                 schedule_in: delay_seconds,
                 unique: [period: 120, keys: [:job_id]]
               )
               |> Oban.insert() do
            {:ok, _} ->
              :ok

            {:error, _reason} ->
              CronJob.complete(job)
              {:error, :insert_failed}
          end

        {:error, _reason} ->
          {:error, :insert_failed}
      end
    end
  end

  @doc "Returns all jobs for the given `agent_id`."
  @spec list_jobs(String.t()) :: [CronJob.t()]
  def list_jobs(agent_id), do: CronJob.for_agent!(agent_id)

  @doc "Returns all scheduled jobs across all agents."
  @spec list_all_jobs() :: [CronJob.t()]
  def list_all_jobs do
    CronJob.all_scheduled!()
  rescue
    _ -> []
  end

  @doc "Recover pending jobs on startup by enqueuing them into Oban."
  @spec recover_jobs() :: :ok
  def recover_jobs do
    list_all_jobs()
    |> Enum.each(fn job ->
      delay = max(CronSchedule.delay_until(job.next_fire_at), 0)
      delay_seconds = div(delay, 1000)

      %{"job_id" => job.id, "agent_id" => job.agent_id, "payload" => job.payload}
      |> ScheduledJob.new(schedule_in: delay_seconds, unique: [period: 120, keys: [:job_id]])
      |> Oban.insert()
    end)
  end
end
