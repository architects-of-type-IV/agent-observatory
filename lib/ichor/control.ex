defmodule Ichor.Control do
  @moduledoc """
  Ash Domain: Agent control plane.

  Manages agents, their configurations, spawning, and coordination.
  Fleet is all agents. Teams are agents with the same group name.
  Blueprints are agent configurations with instructions.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
  end
end
