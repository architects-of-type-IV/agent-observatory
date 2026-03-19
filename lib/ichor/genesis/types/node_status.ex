defmodule Ichor.Genesis.Types.NodeStatus do
  @moduledoc """
  Ash enum type for Genesis Node pipeline stage status.

  Represents progress through the Monad Method pipeline:
  - `:discover`  -- exploring problem space and gathering context
  - `:define`    -- specifying requirements and architecture decisions
  - `:build`     -- implementing the subsystem
  - `:complete`  -- delivered and integrated
  """

  use Ash.Type.Enum, values: [:discover, :define, :build, :complete]
end
