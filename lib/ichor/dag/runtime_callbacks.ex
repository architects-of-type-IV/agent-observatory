defmodule Ichor.Dag.RuntimeCallbacks do
  @moduledoc """
  Boundary for runtime side effects triggered by DAG state transitions.
  """

  alias Ichor.Dag.RunProcess
  alias Ichor.Dag.RuntimeSignals

  @type transition ::
          :job_claimed
          | :job_completed
          | :job_failed
          | :job_reset

  @doc "Emits a signal and syncs the run process after a job state transition."
  @spec after_job_transition(map(), transition()) :: {:ok, map()}
  def after_job_transition(result, transition) do
    emit_transition(result, transition)
    {:ok, result}
  rescue
    _ -> {:ok, result}
  end

  defp emit_transition(result, transition) do
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
