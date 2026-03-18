defmodule Ichor.Dag.RuntimeEventBridge do
  @moduledoc """
  Product-side DAG runtime effects for state transitions.
  """

  alias Ichor.Dag.RunProcess
  alias Ichor.Dag.RuntimeSignals

  @spec after_job_transition(map(), atom()) :: :ok
  def after_job_transition(result, transition) do
    RuntimeSignals.emit_job_transition(result, transition)
    maybe_sync_run_process(result.run_id, result)
    :ok
  end

  defp maybe_sync_run_process(run_id, result) do
    if Code.ensure_loaded?(RunProcess) and function_exported?(RunProcess, :sync_job, 2) do
      RunProcess.sync_job(run_id, result)
    end
  end
end
