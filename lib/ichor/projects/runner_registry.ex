defmodule Ichor.Projects.RunnerRegistry do
  @moduledoc false

  @doc "Returns the via-tuple for Registry-based name lookup."
  @spec via(atom(), String.t()) :: {:via, Registry, {Ichor.Registry, {atom(), String.t()}}}
  def via(kind, run_id), do: {:via, Registry, {Ichor.Registry, {kind, run_id}}}

  @doc "Returns the pid for run_id if alive, or nil."
  @spec lookup(atom(), String.t()) :: pid() | nil
  def lookup(kind, run_id) do
    case Registry.lookup(Ichor.Registry, {kind, run_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Lists all run IDs and PIDs registered under the given kind."
  @spec list_all(atom()) :: [{String.t(), pid()}]
  def list_all(kind) do
    Registry.select(Ichor.Registry, [
      {{{kind, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end
end
