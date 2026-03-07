defmodule Observatory.Fleet.Team do
  @moduledoc """
  A team of agents. Derived from hook events and disk state (TeamWatcher).
  Uses Ash.DataLayer.Simple -- data is loaded by preparations, not persisted.
  """

  use Ash.Resource, domain: Observatory.Fleet

  attributes do
    attribute :name, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :lead_session, :string, public?: true
    attribute :description, :string, public?: true
    attribute :members, {:array, :map}, default: [], public?: true
    attribute :tasks, {:array, :map}, default: [], public?: true
    attribute :source, :atom, constraints: [one_of: [:events, :disk]], public?: true
    attribute :created_at, :utc_datetime_usec, public?: true
    attribute :dead?, :boolean, default: false, public?: true
    attribute :member_count, :integer, default: 0, public?: true
    attribute :health, :atom, constraints: [one_of: [:healthy, :warning, :critical, :unknown]], default: :unknown, public?: true
  end

  actions do
    read :all do
      prepare {Observatory.Fleet.Preparations.LoadTeams, []}
    end

    read :alive do
      prepare {Observatory.Fleet.Preparations.LoadTeams, []}
      filter expr(dead? == false)
    end
  end

  code_interface do
    define :all
    define :alive
  end
end
