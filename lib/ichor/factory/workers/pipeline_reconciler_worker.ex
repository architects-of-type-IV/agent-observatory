defmodule Ichor.Factory.Workers.PipelineReconcilerWorker do
  @moduledoc """
  Oban cron worker that detects orphaned pipelines.

  A pipeline is orphaned when its status is :active but no Runner process exists
  in the Registry. This happens when a crash window leaves the record in :active
  with no corresponding GenServer to advance it.

  Runs every 5 minutes on the :maintenance queue. On each sweep, it reads all
  active pipelines, checks for a live Runner process, and archives any orphan.

  AD-8 safety net: without this, a crashed runner leaves the pipeline stuck in
  :active forever.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1, unique: [period: 280]

  require Logger

  alias Ichor.Factory.{Pipeline, Runner}
  alias Ichor.Signals

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Pipeline.active() do
      {:ok, pipelines} ->
        Enum.each(pipelines, &reconcile/1)
        :ok

      {:error, reason} ->
        Logger.warning(
          "PipelineReconcilerWorker: failed to read active pipelines: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp reconcile(pipeline) do
    if Runner.lookup(:pipeline, pipeline.id) do
      Logger.debug("PipelineReconcilerWorker: pipeline #{pipeline.id} has live runner, skipping")
    else
      Logger.warning(
        "PipelineReconcilerWorker: orphaned pipeline detected id=#{pipeline.id} label=#{pipeline.label}"
      )

      case Pipeline.archive(pipeline) do
        {:ok, _archived} ->
          Signals.emit(:pipeline_reconciled, %{
            pipeline_id: pipeline.id,
            run_id: pipeline.id,
            action: :archived
          })

          Logger.info("PipelineReconcilerWorker: archived orphaned pipeline #{pipeline.id}")

        {:error, reason} ->
          Logger.warning(
            "PipelineReconcilerWorker: failed to archive pipeline #{pipeline.id}: #{inspect(reason)}"
          )
      end
    end
  end
end
