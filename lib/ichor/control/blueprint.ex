defmodule Ichor.Control.Blueprint do
  @moduledoc """
  A saved team blueprint. Persists team configuration so users can
  design, save, reload, and launch team compositions from the Workshop canvas.

  Agents, spawn links, and communication rules are stored as embedded JSON arrays
  rather than separate DB-backed resources.
  """

  use Ash.Resource,
    domain: Ichor.Control,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("workshop_blueprints")
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

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:name, :strategy, :default_model, :cwd, :agents, :spawn_links, :comm_rules])
    end

    update :update do
      accept([:name, :strategy, :default_model, :cwd, :agents, :spawn_links, :comm_rules])
      require_atomic?(false)
    end

    read :by_id do
      argument(:id, :uuid, allow_nil?: false)
      get?(true)
      filter(expr(id == ^arg(:id)))
    end

    read :by_name do
      argument(:name, :string, allow_nil?: false)
      get?(true)
      filter(expr(name == ^arg(:name)))
    end

    read :list_all do
      prepare(build(sort: [inserted_at: :desc]))
    end
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
    define(:destroy)
    define(:by_id, args: [:id])
    define(:by_name, args: [:name])
    define(:list_all)
  end

  identities do
    identity(:unique_name, [:name])
  end
end
