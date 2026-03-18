defmodule Ichor.Archon do
  @moduledoc """
  Archon -- the Architect's agent interface to ICHOR IV.

  Archon is the sovereign coordinator of the fleet. It speaks on behalf
  of the Architect, queries fleet state, sends messages to agents, and
  will eventually integrate with the Memories knowledge graph for
  long-term recall.
  """
  use Ash.Domain

  resources do
  end
end
