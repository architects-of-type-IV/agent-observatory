defmodule Ichor.Workshop.Team do
  @moduledoc """
  A saved Workshop team definition.

  Persists the authored team configuration so the frontend can design, save,
  reload, and spawn teams from the Workshop canvas.
  """

  use Ash.Resource,
    domain: Ichor.Workshop,
    data_layer: AshPostgres.DataLayer

  alias Ichor.Workshop.{Spawn, TeamMember}

  postgres do
    repo(Ichor.Repo)
    table("workshop_teams")
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

    attribute :agents, {:array, Ichor.Workshop.AgentSlot} do
      default([])
      public?(true)
    end

    attribute :spawn_links, {:array, Ichor.Workshop.SpawnLink} do
      default([])
      public?(true)
    end

    attribute :comm_rules, {:array, Ichor.Workshop.CommRule} do
      default([])
      public?(true)
    end

    timestamps()
  end

  relationships do
    has_many :members, TeamMember do
      destination_attribute(:team_id)
    end
  end

  actions do
    read :read do
      description("List all saved team designs.")
    end

    destroy :destroy do
      description("Delete a saved team design.")
    end

    create :create do
      description("Save a new team design to the Workshop.")
      accept([:name, :strategy, :default_model, :cwd, :agents, :spawn_links, :comm_rules])
    end

    update :update do
      description("Update an existing team design in the Workshop.")
      accept([:name, :strategy, :default_model, :cwd, :agents, :spawn_links, :comm_rules])
    end

    read :by_name do
      description("Look up a saved team design by its unique name.")
      argument(:name, :string, allow_nil?: false)
      get?(true)
      filter(expr(name == ^arg(:name)))
    end

    read :list_all do
      description("List all saved team designs, sorted newest first.")
      prepare(build(sort: [inserted_at: :desc]))
    end

    action :spawn_team, :map do
      description("Spawn a live team from a saved Workshop design by name.")
      argument(:name, :string, allow_nil?: false)

      run(fn input, _context ->
        Spawn.spawn_team(input.arguments.name)
      end)
    end
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
    define(:destroy)
    define(:by_id, action: :read, get_by: [:id])
    define(:by_name, args: [:name])
    define(:list_all)
    define(:spawn_team, args: [:name])
  end

  identities do
    identity(:unique_name, [:name])
  end
end
