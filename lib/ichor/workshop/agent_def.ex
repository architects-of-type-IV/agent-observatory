defmodule Ichor.Workshop.AgentDef do
  @moduledoc """
  A persisted Workshop agent definition.

  Stores authored agent configurations in the database. Each AgentDef belongs
  to an AgentType (required) and optionally to a Team. This is the design-time
  complement to the runtime Workshop.Agent (ETS-backed).
  """

  use Ash.Resource,
    domain: Ichor.Workshop,
    data_layer: AshPostgres.DataLayer

  alias Ichor.Workshop.{AgentType, Team}

  postgres do
    repo(Ichor.Repo)
    table("workshop_agents")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :role, :string do
      public?(true)
    end

    attribute :model, :string do
      allow_nil?(false)
      default("sonnet")
      public?(true)
    end

    attribute :cwd, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :instructions, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :permission, :string do
      allow_nil?(false)
      default("default")
      public?(true)
    end

    attribute :file_scope, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :quality_gates, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :tool_scope, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :position, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :canvas_x, :integer do
      allow_nil?(false)
      default(40)
      public?(true)
    end

    attribute :canvas_y, :integer do
      allow_nil?(false)
      default(30)
      public?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :agent_type, AgentType do
      allow_nil?(false)
      attribute_public?(true)
    end

    belongs_to :team, Team do
      allow_nil?(true)
      attribute_public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :name,
        :role,
        :model,
        :cwd,
        :instructions,
        :permission,
        :file_scope,
        :quality_gates,
        :tool_scope,
        :position,
        :canvas_x,
        :canvas_y,
        :agent_type_id,
        :team_id
      ])
    end

    update :update do
      primary?(true)

      accept([
        :name,
        :role,
        :model,
        :cwd,
        :instructions,
        :permission,
        :file_scope,
        :quality_gates,
        :tool_scope,
        :position,
        :canvas_x,
        :canvas_y,
        :agent_type_id,
        :team_id
      ])
    end

    read :for_team do
      argument(:team_id, :uuid, allow_nil?: false)
      filter(expr(team_id == ^arg(:team_id)))
      prepare(build(sort: [position: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
    define(:destroy)
    define(:by_id, action: :read, get_by: [:id])
    define(:for_team, args: [:team_id])
  end
end
