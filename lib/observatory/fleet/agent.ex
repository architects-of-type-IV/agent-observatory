defmodule Observatory.Fleet.Agent do
  @moduledoc """
  An observed agent in the fleet. Derived from EventBuffer events and tmux sessions.
  Uses Ash.DataLayer.Simple -- data is loaded by preparations, not persisted.
  """

  use Ash.Resource, domain: Observatory.Fleet

  attributes do
    attribute :agent_id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :role, :string, public?: true
    attribute :model, :string, public?: true
    attribute :status, :atom, constraints: [one_of: [:active, :idle, :ended]], public?: true
    attribute :health, :atom, constraints: [one_of: [:healthy, :warning, :critical, :unknown]], default: :unknown, public?: true
    attribute :current_tool, :map, public?: true
    attribute :event_count, :integer, default: 0, public?: true
    attribute :tool_count, :integer, default: 0, public?: true
    attribute :cwd, :string, public?: true
    attribute :source_app, :string, public?: true
    attribute :project, :string, public?: true
    attribute :health_issues, {:array, :map}, default: [], public?: true
    attribute :team_name, :string, public?: true
    attribute :tmux_session, :string, public?: true
    attribute :recent_activity, {:array, :map}, default: [], public?: true
  end

  actions do
    read :all do
      prepare {Observatory.Fleet.Preparations.LoadAgents, []}
    end

    read :active do
      prepare {Observatory.Fleet.Preparations.LoadAgents, []}
      filter expr(status != :ended)
    end

    read :in_team do
      argument :team_name, :string, allow_nil?: false
      prepare {Observatory.Fleet.Preparations.LoadAgents, []}
      filter expr(team_name == ^arg(:team_name))
    end
  end

  code_interface do
    define :all
    define :active
    define :in_team, args: [:team_name]
  end
end
