defmodule Ichor.Workshop.Presets.TeamPreset do
  @moduledoc """
  Typed preset definition for Workshop team templates.

  Temporary scaffolding -- presets are hardcoded mock data that the
  /workshop page will fully replace once functional. Uses the same
  Ash embedded resource structs (`AgentSlot`, `SpawnLink`, `CommRule`)
  as the DB `Team` resource so shapes stay aligned.

  `dispatch_hub_id` identifies which base agent dynamically-injected
  workers connect to for comm rules (e.g. the lead in a pipeline team).
  When nil, workers get no auto-generated comm rules.
  """

  alias Ichor.Workshop.{AgentSlot, CommRule, SpawnLink}

  @enforce_keys [:label, :color, :team_name, :strategy, :model, :agents, :next_id, :links, :rules]
  defstruct [
    :label,
    :color,
    :team_name,
    :strategy,
    :model,
    :agents,
    :next_id,
    :links,
    :rules,
    dispatch_hub_id: nil
  ]

  @type t :: %__MODULE__{
          label: String.t(),
          color: String.t(),
          team_name: String.t(),
          strategy: String.t(),
          model: String.t(),
          agents: [AgentSlot.t()],
          next_id: pos_integer(),
          links: [SpawnLink.t()],
          rules: [CommRule.t()],
          dispatch_hub_id: integer() | nil
        }
end
