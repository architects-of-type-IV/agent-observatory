defmodule Ichor.Factory.Workers.ArchiveRunWorker do
  @moduledoc """
  Archives a pipeline run detected as needing cleanup by TeamWatchdog.

  Idempotent: no-ops if the pipeline is already archived or not found.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 60, keys: [:run_id]]

  require Logger

  alias Ichor.Factory.Pipeline
  alias Ichor.Signals

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    case Pipeline.get(run_id) do
      {:ok, %{status: :active} = pipeline} ->
        case Pipeline.archive(pipeline) do
          {:ok, archived} ->
            Signals.emit(:pipeline_archived, %{
              run_id: run_id,
              label: archived.label,
              reason: "watchdog"
            })

            :ok

          {:error, reason} ->
            Logger.warning(
              "[ArchiveRunWorker] Failed to archive pipeline #{run_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:ok, _pipeline} ->
        # Already archived, completed, or failed -- no-op
        :ok

      {:error, %Ash.Error.Query.NotFound{}} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[ArchiveRunWorker] Failed to fetch pipeline #{run_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
