defmodule Ichor.Control.Types.AgentStatus do
  @moduledoc """
  Ash enum type for agent and session lifecycle status.

  - `:active` -- agent is currently running
  - `:idle`   -- agent is alive but not processing
  - `:ended`  -- agent has terminated
  """

  use Ash.Type.Enum, values: [:active, :idle, :ended]
end
