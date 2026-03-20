defmodule Ichor.Factory do
  @moduledoc """
  Ash Domain: MES planning and pipeline execution.

  Owns MES projects, planning artifacts, DAG runs, jobs, and the execution
  lifecycle that turns planned work into wave-based delivery.
  """

  use Ash.Domain

  resources do
    resource(Ichor.Factory.Project)
    resource(Ichor.Factory.Node)
    resource(Ichor.Factory.Artifact)
    resource(Ichor.Factory.RoadmapItem)
    resource(Ichor.Factory.Run)
    resource(Ichor.Factory.Job)
  end
end
