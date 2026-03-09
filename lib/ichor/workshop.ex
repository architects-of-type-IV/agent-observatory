defmodule Ichor.Workshop do
  @moduledoc """
  Workshop domain -- design, save, and launch team blueprints.
  The canonical entry point for all workshop operations.
  """

  use Ash.Domain

  resources do
    resource Ichor.Workshop.AgentType
    resource Ichor.Workshop.TeamBlueprint
    resource Ichor.Workshop.AgentBlueprint
    resource Ichor.Workshop.SpawnLink
    resource Ichor.Workshop.CommRule
  end
end
