defmodule Observatory.MeshSupervisor do
  @moduledoc """
  Supervises mesh/DAG services: CausalDAG, TopologyBuilder, and EventBridge.

  Uses rest_for_one: CausalDAG must start first (TopologyBuilder subscribes to
  per-session DAG topics, EventBridge inserts into DAG). If CausalDAG crashes,
  downstream services restart so they can re-subscribe.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Observatory.Mesh.CausalDAG, []},
      {Observatory.Gateway.TopologyBuilder, []},
      {Observatory.Gateway.EventBridge, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
