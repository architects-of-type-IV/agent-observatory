defmodule Ichor.Dag.Types.JobPriority do
  @moduledoc """
  Ash enum type for DAG job priority levels.
  """

  use Ash.Type.Enum, values: [:critical, :high, :medium, :low]
end
