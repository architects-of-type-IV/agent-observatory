defmodule Ichor.Dag.RunSupervisor do
  @moduledoc """
  DynamicSupervisor facade for Dag.RunProcess children.

  The underlying DynamicSupervisor is named `Ichor.Dag.DynRunSupervisor`
  and is started by `Ichor.Dag.Supervisor`.
  """

  alias Ichor.Dag.RunProcess

  @supervisor Ichor.Dag.DynRunSupervisor

  @spec start_run(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_run(opts) do
    child_spec = {RunProcess, opts}
    DynamicSupervisor.start_child(@supervisor, child_spec)
  end

  @spec stop_run(String.t()) :: :ok | {:error, :not_found}
  def stop_run(run_id) do
    case Registry.lookup(Ichor.Registry, {:dag_run, run_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(@supervisor, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @spec list_active() :: [{String.t(), pid()}]
  def list_active do
    Registry.select(Ichor.Registry, [
      {{{:dag_run, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end
end
