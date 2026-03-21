defmodule Ichor.Factory.Workers.ResetRunTasksWorker do
  @moduledoc """
  Resets in-progress pipeline tasks for a run detected as needing cleanup by TeamWatchdog.

  Idempotent: no-ops if no in-progress tasks exist for the given run_id.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 60, keys: [:run_id]]

  require Logger

  alias Ichor.Factory.PipelineTask

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    case PipelineTask.by_run(run_id) do
      {:ok, pipeline_tasks} ->
        in_progress = Enum.filter(pipeline_tasks, &(&1.status == :in_progress))

        errors =
          Enum.flat_map(in_progress, fn task ->
            case PipelineTask.reset(task) do
              {:ok, _} ->
                []

              {:error, reason} ->
                Logger.warning(
                  "[ResetRunTasksWorker] Failed to reset task #{task.id} for run #{run_id}: #{inspect(reason)}"
                )

                [reason]
            end
          end)

        case errors do
          [] -> :ok
          [first | _] -> {:error, first}
        end

      {:error, reason} ->
        Logger.warning(
          "[ResetRunTasksWorker] Failed to fetch tasks for run #{run_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
