defmodule Ichor.Projects.Runner.Hooks.DAG do
  @moduledoc """
  DAG-specific runner hook implementations.

  Handles periodic stale job detection, health checks, write-through
  sync, and run completion recording.
  """

  alias Ichor.Projects.{Exporter, HealthChecker, Job, Run, RuntimeSignals}

  @stale_threshold_min 10

  @doc "Periodic check: resets stale in-progress jobs."
  @spec check_stale(struct()) :: :ok
  def check_stale(state) do
    with {:ok, jobs} <- Job.by_run(state.run_id) do
      now = DateTime.utc_now()

      jobs
      |> Enum.filter(&(to_string(&1.status) == "in_progress" and stale?(&1, now)))
      |> Enum.each(&Job.reset/1)
    end

    :ok
  end

  @doc "Periodic check: emits a health report signal."
  @spec check_health(struct()) :: :ok
  def check_health(state) do
    case HealthChecker.check(state.run_id) do
      {:ok, report} ->
        RuntimeSignals.emit_health_report(state.run_id, report.healthy, length(report.issues))

      _ ->
        :ok
    end

    :ok
  end

  @doc "Write-through sync command: exports a single job to tasks.jsonl."
  @spec sync_job(struct(), struct() | map()) :: {:noreply, struct()}
  def sync_job(state, job) do
    Task.start(fn -> Exporter.sync_to_file(job, state.project_path) end)
    {:noreply, state}
  end

  @doc "Called when the coordinator delivers to operator. Records run completion."
  @spec on_complete(struct()) :: :ok
  def on_complete(state) do
    with {:ok, run} <- Run.get(state.run_id) do
      Run.complete(run)
      RuntimeSignals.emit_run_completed(state.run_id, run.label)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp stale?(%{updated_at: nil}, _now), do: true

  defp stale?(%{updated_at: ts}, now) do
    DateTime.diff(now, ts, :minute) > @stale_threshold_min
  end
end
