defmodule Ichor.Control do
  @moduledoc """
  Ash Domain: Agent control plane.

  Manages agents, their configurations, spawning, and coordination.
  Fleet is all agents. Teams are agents with the same group name.
  Blueprints are agent configurations with instructions.
  """
  use Ash.Domain

  resources do
    resource(Ichor.Control.Agent)
    resource(Ichor.Control.Team)
    resource(Ichor.Control.Blueprint)
    resource(Ichor.Control.AgentType)
    resource(Ichor.Gateway.WebhookDelivery)
    resource(Ichor.Gateway.CronJob)
  end
end
