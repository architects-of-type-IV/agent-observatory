defmodule Ichor.Dag.Types.RunSource do
  @moduledoc """
  Ash enum type for DAG run origin source.
  """

  use Ash.Type.Enum, values: [:genesis, :imported]
end
