defmodule Ichor.Projects do
  @moduledoc """
  Ash Domain: Project lifecycle from planning through execution.

  Genesis is planning. DAG resolves dependencies into execution waves.
  MES is the project lifecycle container. A swarm is coordinated agents
  executing wave-ready tasks.
  """
  use Ash.Domain

  resources do
    resource(Ichor.Projects.Project)
    resource(Ichor.Projects.Node)
    resource(Ichor.Projects.Artifact)
    resource(Ichor.Projects.RoadmapItem)
    resource(Ichor.Projects.Run)
    resource(Ichor.Projects.Job)
  end
end
