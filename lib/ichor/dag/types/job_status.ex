defmodule Ichor.Dag.Types.JobStatus do
  @moduledoc """
  Ash enum type for DAG job lifecycle status.
  """

  use Ash.Type.Enum, values: [:pending, :in_progress, :completed, :failed]
end
