defmodule Observatory.Workshop do
  @moduledoc """
  Workshop domain -- design, save, and launch team blueprints.
  The canonical entry point for all workshop operations.
  """

  use Ash.Domain

  resources do
    resource Observatory.Workshop.AgentType
    resource Observatory.Workshop.TeamBlueprint
    resource Observatory.Workshop.AgentBlueprint
    resource Observatory.Workshop.SpawnLink
    resource Observatory.Workshop.CommRule
  end
end
