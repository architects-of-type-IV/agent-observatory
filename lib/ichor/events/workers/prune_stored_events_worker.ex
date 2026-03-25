defmodule Ichor.Events.Workers.PruneStoredEventsWorker do
  @moduledoc """
  Oban maintenance worker that prunes StoredEvent records older than the retention window.

  Runs daily at 3am. Uses Ash bulk destroy via the :prune action which filters
  events by occurred_at < before cutoff.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  require Logger

  @retention_days 7

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days, :day)

    result =
      Ichor.Events.StoredEvent
      |> Ash.Query.new()
      |> Ash.bulk_destroy(:prune, %{before: cutoff}, return_errors?: true)

    case result do
      %Ash.BulkResult{status: :success} ->
        Logger.info("[PruneStoredEventsWorker] Pruned stored events older than #{cutoff}")
        :ok

      %Ash.BulkResult{status: :error, errors: errors} ->
        Logger.warning("[PruneStoredEventsWorker] Prune failed: #{inspect(errors)}")
        {:error, errors}
    end
  end
end
