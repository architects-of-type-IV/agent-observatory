defmodule Ichor.Mesh.Supervisor do
  @moduledoc """
  Supervises mesh topology services: the causal DAG and the event bridge.

  Uses rest_for_one: CausalDAG must start first (EventBridge inserts
  into DAG and subscribes to per-session DAG topics). If CausalDAG
  crashes, EventBridge restarts so it can re-subscribe.
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
      {Ichor.Mesh.CausalDAG, []},
      {Ichor.Mesh.EventBridge, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 60)
  end
end
