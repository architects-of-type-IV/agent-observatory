defmodule Ichor.Projects do
  @moduledoc """
  Ash Domain: Project lifecycle from planning through execution.

  Genesis is planning. DAG resolves dependencies into execution waves.
  MES is the project lifecycle container. A swarm is coordinated agents
  executing wave-ready tasks.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
  end
end
