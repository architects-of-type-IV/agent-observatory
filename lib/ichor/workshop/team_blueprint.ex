defmodule Ichor.Workshop.TeamBlueprint do
  @moduledoc """
  A saved team blueprint. Persists team configuration so users can
  design, save, reload, and launch team compositions from the Workshop canvas.
  """

  use Ash.Resource,
    domain: Ichor.Workshop,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("workshop_team_blueprints")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :strategy, :string do
      allow_nil?(false)
      default("one_for_one")
      public?(true)
    end

    attribute :default_model, :string do
      allow_nil?(false)
      default("sonnet")
      public?(true)
    end

    attribute :cwd, :string do
      default("")
      public?(true)
    end

    timestamps()
  end

  relationships do
    has_many :agent_blueprints, Ichor.Workshop.AgentBlueprint
    has_many :spawn_links, Ichor.Workshop.SpawnLink
    has_many :comm_rules, Ichor.Workshop.CommRule
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :strategy, :default_model, :cwd]

      argument :agent_blueprints, {:array, :map}, default: []
      argument :spawn_links, {:array, :map}, default: []
      argument :comm_rules, {:array, :map}, default: []

      change manage_relationship(:agent_blueprints, type: :direct_control)
      change manage_relationship(:spawn_links, type: :direct_control)
      change manage_relationship(:comm_rules, type: :direct_control)
    end

    update :update do
      accept [:name, :strategy, :default_model, :cwd]
      require_atomic?(false)

      argument :agent_blueprints, {:array, :map}
      argument :spawn_links, {:array, :map}
      argument :comm_rules, {:array, :map}

      change manage_relationship(:agent_blueprints, type: :direct_control)
      change manage_relationship(:spawn_links, type: :direct_control)
      change manage_relationship(:comm_rules, type: :direct_control)
    end

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
      prepare build(load: [:agent_blueprints, :spawn_links, :comm_rules])
    end
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :by_id, args: [:id]
  end

  identities do
    identity :unique_name, [:name]
  end
end
