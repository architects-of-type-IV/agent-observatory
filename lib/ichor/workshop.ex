defmodule Ichor.Workshop do
  @moduledoc """
  Ash Domain: Workshop team and agent authoring.

  Owns reusable agent types, saved team definitions, persisted team members,
  and the runtime-facing agent/team resource surfaces used by the frontend.
  """

  use Ash.Domain

  resources do
    resource(Ichor.Control.Agent)
    resource(Ichor.Control.Team)
    resource(Ichor.Workshop.Team)
    resource(Ichor.Workshop.TeamMember)
    resource(Ichor.Workshop.AgentType)
  end
end
