defmodule Ichor.Workshop.Team do
  @moduledoc """
  A saved Workshop team definition.

  Persists the authored team configuration so the frontend can design, save,
  reload, and spawn teams from the Workshop canvas.
  """

  use Ash.Resource,
    domain: Ichor.Workshop,
    data_layer: AshSqlite.DataLayer

  alias Ichor.Workshop.{Spawn, TeamMember}

  sqlite do
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

    attribute :agents, {:array, :map} do
      default([])
      public?(true)
    end

    attribute :spawn_links, {:array, :map} do
      default([])
      public?(true)
    end

    attribute :comm_rules, {:array, :map} do
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
    defaults([:read, :destroy])

    create :create do
      accept([:name, :strategy, :default_model, :cwd, :agents, :spawn_links, :comm_rules])
    end

    update :update do
      accept([:name, :strategy, :default_model, :cwd, :agents, :spawn_links, :comm_rules])
      require_atomic?(false)
    end

    read :by_name do
      argument(:name, :string, allow_nil?: false)
      get?(true)
      filter(expr(name == ^arg(:name)))
    end

    read :list_all do
      prepare(build(sort: [inserted_at: :desc]))
    end

    action :spawn_team, :map do
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
