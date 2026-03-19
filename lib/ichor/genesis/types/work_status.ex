defmodule Ichor.Genesis.Types.WorkStatus do
  @moduledoc """
  Ash enum type for Genesis task and subtask work lifecycle status.
  """

  use Ash.Type.Enum, values: [:pending, :in_progress, :completed, :blocked]
end
