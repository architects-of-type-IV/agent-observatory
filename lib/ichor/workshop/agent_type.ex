defmodule Ichor.Workshop.AgentType do
  @moduledoc """
  A reusable agent archetype. Defines default configuration for agents
  of this type. Used by presets and the team builder to stamp out agents.
  """

  use Ash.Resource,
    domain: Ichor.Workshop,
    data_layer: AshPostgres.DataLayer

  postgres do
    repo(Ichor.Repo)
    table("workshop_agent_types")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
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

    attribute :default_provider, :atom do
      constraints(one_of: [:claude, :gemini, :codex, :shell])
      default(:claude)
      public?(true)
    end

    attribute :default_permission, :string do
      allow_nil?(false)
      default("default")
      public?(true)
    end

    attribute :default_persona, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :default_file_scope, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :default_quality_gates, :string do
      allow_nil?(false)
      default("mix compile --warnings-as-errors")
      public?(true)
    end

    attribute :default_tools, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :system_prompt, :string do
      public?(true)
    end

    attribute :color, :string do
      allow_nil?(false)
      default("")
      public?(true)
      description("Optional hex color for canvas display")
    end

    attribute :sort_order, :integer do
      allow_nil?(false)
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
        :description,
        :capability,
        :default_model,
        :default_provider,
        :default_permission,
        :default_persona,
        :default_file_scope,
        :default_quality_gates,
        :default_tools,
        :system_prompt,
        :color,
        :sort_order
      ])
    end

    update :update do
      primary?(true)

      accept([
        :name,
        :description,
        :capability,
        :default_model,
        :default_provider,
        :default_permission,
        :default_persona,
        :default_file_scope,
        :default_quality_gates,
        :default_tools,
        :system_prompt,
        :color,
        :sort_order
      ])
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
    define(:by_id, action: :read, get_by: [:id])
    define(:sorted)
  end
end
