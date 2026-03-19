defmodule Ichor.Workshop.AgentBlueprint do
  @moduledoc """
  An agent node within a team blueprint. Stores agent configuration
  and canvas position for the visual team builder.
  """

  use Ash.Resource,
    domain: Ichor.Control,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("workshop_agent_blueprints")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :slot, :integer do
      allow_nil?(false)
      public?(true)
      description("Stable integer ID for spawn/comm link references within a blueprint")
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :capability, :string do
      allow_nil?(false)
      default("builder")
      public?(true)
    end

    attribute :model, :string do
      allow_nil?(false)
      default("sonnet")
      public?(true)
    end

    attribute :permission, :string do
      allow_nil?(false)
      default("default")
      public?(true)
    end

    attribute :persona, :string do
      default("")
      public?(true)
    end

    attribute :file_scope, :string do
      default("")
      public?(true)
    end

    attribute :quality_gates, :string do
      default("mix compile --warnings-as-errors")
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
    belongs_to :team_blueprint, Ichor.Workshop.TeamBlueprint do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :slot,
        :name,
        :capability,
        :model,
        :permission,
        :persona,
        :file_scope,
        :quality_gates,
        :canvas_x,
        :canvas_y,
        :team_blueprint_id
      ])
    end

    update :update do
      primary?(true)

      accept([
        :name,
        :capability,
        :model,
        :permission,
        :persona,
        :file_scope,
        :quality_gates,
        :canvas_x,
        :canvas_y
      ])
    end
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
    define(:destroy)
  end
end
