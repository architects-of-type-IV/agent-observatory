defmodule Ichor.Dag.Supervisor do
  @moduledoc """
  Top-level supervisor for the DAG execution subsystem.

  Supervision tree:

      Dag.Supervisor
        +-- DynamicSupervisor (Ichor.Dag.DynRunSupervisor)  # one child per active run
  """

  use Supervisor

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {DynamicSupervisor, name: Ichor.Dag.DynRunSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
