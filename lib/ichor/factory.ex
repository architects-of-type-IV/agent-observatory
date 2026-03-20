defmodule Ichor.Factory do
  @moduledoc """
  Ash Domain: MES planning and pipeline execution.

  Owns MES projects, planning artifacts, pipelines, pipeline tasks, and the execution
  lifecycle that turns planned work into wave-based delivery.
  """

  use Ash.Domain

  resources do
    resource(Ichor.Factory.Project)
    resource(Ichor.Factory.Floor)
    resource(Ichor.Factory.Pipeline)
    resource(Ichor.Factory.PipelineTask)
  end
end
