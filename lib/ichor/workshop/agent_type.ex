defmodule Ichor.Workshop.AgentType do
  @moduledoc """
  A reusable agent archetype. Defines default configuration for agents
  of this type. Used by presets and the team builder to stamp out agents.
  """

  use Ash.Resource,
    domain: Ichor.Workshop,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("workshop_agent_types")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :capability, :string do
      allow_nil?(false)
      default("builder")
      public?(true)
    end

    attribute :default_model, :string do
      allow_nil?(false)
      default("sonnet")
      public?(true)
    end

    attribute :default_permission, :string do
      allow_nil?(false)
      default("default")
      public?(true)
    end

    attribute :default_persona, :string do
      default("")
      public?(true)
    end

    attribute :default_file_scope, :string do
      default("")
      public?(true)
    end

    attribute :default_quality_gates, :string do
      default("mix compile --warnings-as-errors")
      public?(true)
    end

    attribute :color, :string do
      default("")
      public?(true)
      description("Optional hex color for canvas display")
    end

    attribute :sort_order, :integer do
      default(0)
      public?(true)
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :name,
        :capability,
        :default_model,
        :default_permission,
        :default_persona,
        :default_file_scope,
        :default_quality_gates,
        :color,
        :sort_order
      ])
    end

    update :update do
      primary?(true)

      accept([
        :name,
        :capability,
        :default_model,
        :default_permission,
        :default_persona,
        :default_file_scope,
        :default_quality_gates,
        :color,
        :sort_order
      ])
    end

    read :by_id do
      argument(:id, :uuid, allow_nil?: false)
      get?(true)
      filter(expr(id == ^arg(:id)))
    end

    read :sorted do
      prepare(build(sort: [sort_order: :asc, name: :asc]))
    end
  end

  identities do
    identity(:unique_name, [:name])
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
    define(:destroy)
    define(:by_id, args: [:id])
    define(:sorted)
  end
end
