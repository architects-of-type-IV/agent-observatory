defmodule Ichor.Dag.RuntimeCallbacks do
  @moduledoc """
  Boundary for runtime side effects triggered by DAG state transitions.
  """

  @type transition ::
          :job_claimed
          | :job_completed
          | :job_failed
          | :job_reset

  @spec after_job_transition(map(), transition()) :: {:ok, map()}
  def after_job_transition(result, transition) do
    runtime_callbacks_module().after_job_transition(result, transition)
    {:ok, result}
  rescue
    _ -> {:ok, result}
  end

  defp runtime_callbacks_module do
    Application.get_env(
      :ichor_dag,
      :runtime_callbacks_module,
      Module.concat([Ichor, Dag, RuntimeEventBridge])
    )
  end
end
