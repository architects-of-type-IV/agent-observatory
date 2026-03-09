defmodule Ichor.Fleet.Team do
  @moduledoc """
  A team of agents. The Ash resource provides both read access (via preparations
  that load from Registry/events/disk) and write operations (via generic actions
  that delegate to the BEAM-native DynamicSupervisor layer).

  This is the canonical entry point for all team operations.
  """

  use Ash.Resource, domain: Ichor.Fleet

  attributes do
    attribute :name, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :lead_session, :string, public?: true
    attribute :description, :string, public?: true
    attribute :members, {:array, :map}, default: [], public?: true
    attribute :tasks, {:array, :map}, default: [], public?: true
    attribute :source, :atom, constraints: [one_of: [:events, :beam]], public?: true
    attribute :created_at, :utc_datetime_usec, public?: true
    attribute :dead?, :boolean, default: false, public?: true
    attribute :member_count, :integer, default: 0, public?: true
    attribute :health, :atom, constraints: [one_of: [:healthy, :warning, :critical, :unknown]], default: :unknown, public?: true
  end

  actions do
    # ── Reads ────────────────────────────────────────────────────────

    read :all do
      prepare {Ichor.Fleet.Preparations.LoadTeams, []}
    end

    read :alive do
      prepare {Ichor.Fleet.Preparations.LoadTeams, []}
      filter expr(dead? == false)
    end

    # ── Lifecycle ────────────────────────────────────────────────────

    action :create_team, :map do
      description "Create a new team with a DynamicSupervisor."

      argument :name, :string, allow_nil?: false, description: "Team name"
      argument :strategy, :atom, default: :one_for_one, description: "Restart strategy"
      argument :project, :string, description: "Project key or path"
      argument :description, :string, description: "Team description"

      run fn input, _context ->
        args = input.arguments
        opts = [name: args.name, strategy: args.strategy]
        opts = if args[:project], do: Keyword.put(opts, :project, args.project), else: opts

        case Ichor.Fleet.FleetSupervisor.create_team(opts) do
          {:ok, pid} ->
            {:ok, %{name: args.name, pid: inspect(pid), status: :created, strategy: args.strategy}}

          {:error, :already_exists} ->
            {:ok, %{name: args.name, status: :already_exists}}

          {:error, reason} ->
            {:error, "Failed to create team: #{inspect(reason)}"}
        end
      end
    end

    action :disband, :map do
      description "Disband a team, terminating all its members."
      argument :name, :string, allow_nil?: false

      run fn input, _context ->
        case Ichor.Fleet.FleetSupervisor.disband_team(input.arguments.name) do
          :ok -> {:ok, %{name: input.arguments.name, status: :disbanded}}
          {:error, :not_found} -> {:error, "Team not found: #{input.arguments.name}"}
          error -> {:error, "Failed to disband: #{inspect(error)}"}
        end
      end
    end

    action :spawn_member, :map do
      description "Spawn a new agent as a member of this team."

      argument :team_name, :string, allow_nil?: false, description: "Team to spawn into"
      argument :agent_id, :string, allow_nil?: false, description: "Unique agent identifier"
      argument :role, :atom, default: :worker, description: "Agent role"
      argument :backend, :map, description: "Backend transport config"

      run fn input, _context ->
        args = input.arguments
        opts = [id: args.agent_id, role: args.role]
        opts = if args[:backend], do: Keyword.put(opts, :backend, args.backend), else: opts

        case Ichor.Fleet.TeamSupervisor.spawn_member(args.team_name, opts) do
          {:ok, pid} ->
            {:ok, %{agent_id: args.agent_id, team: args.team_name, pid: inspect(pid), status: :spawned}}

          {:error, reason} ->
            {:error, "Failed to spawn member: #{inspect(reason)}"}
        end
      end
    end
  end

  code_interface do
    # Reads
    define :all
    define :alive
    # Lifecycle
    define :create_team, args: [:name]
    define :disband, args: [:name]
    define :spawn_member, args: [:team_name, :agent_id]
  end
end
