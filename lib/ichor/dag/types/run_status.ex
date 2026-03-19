defmodule Ichor.Dag.Types.RunStatus do
  @moduledoc """
  Ash enum type for DAG run lifecycle status.
  """

  use Ash.Type.Enum, values: [:active, :completed, :failed, :archived]
end
