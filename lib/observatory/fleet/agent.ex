defmodule Observatory.Fleet.Agent do
  @moduledoc """
  An agent in the fleet. The Ash resource provides both read access (via preparations
  that load from Registry/events) and write operations (via generic actions that
  delegate to the BEAM-native GenServer layer).

  This is the canonical entry point for all agent operations.
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
    # ── Reads ────────────────────────────────────────────────────────

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

    # ── Lifecycle ────────────────────────────────────────────────────

    action :spawn, :map do
      description "Spawn a new agent process in the fleet."

      argument :id, :string, allow_nil?: false, description: "Unique agent identifier"
      argument :role, :atom, default: :worker, description: "Agent role"
      argument :team_name, :string, description: "Team to join (nil for standalone)"
      argument :backend, :map, description: "Backend transport config"
      argument :capabilities, {:array, :atom}, default: [], description: "Agent capabilities"
      argument :instructions, :string, description: "Initial instruction overlay"

      run fn input, _context ->
        args = input.arguments
        opts = [id: args.id, role: args.role, capabilities: args.capabilities]
        opts = if args[:instructions], do: Keyword.put(opts, :instructions, args.instructions), else: opts
        opts = if args[:backend], do: Keyword.put(opts, :backend, args.backend), else: opts

        case spawn_in_fleet(args[:team_name], opts) do
          {:ok, pid} ->
            {:ok, %{agent_id: args.id, pid: inspect(pid), status: :active}}

          {:error, {:already_started, pid}} ->
            {:ok, %{agent_id: args.id, pid: inspect(pid), status: :active, note: "already running"}}

          {:error, reason} ->
            {:error, "Failed to spawn agent: #{inspect(reason)}"}
        end
      end
    end

    action :pause_agent, :map do
      description "Pause an agent (buffers messages, stops backend delivery)."
      argument :agent_id, :string, allow_nil?: false

      run fn input, _context ->
        case Observatory.Fleet.AgentProcess.pause(input.arguments.agent_id) do
          :ok -> {:ok, %{agent_id: input.arguments.agent_id, status: :paused}}
          error -> {:error, "Failed to pause: #{inspect(error)}"}
        end
      end
    end

    action :resume_agent, :map do
      description "Resume a paused agent (delivers buffered messages)."
      argument :agent_id, :string, allow_nil?: false

      run fn input, _context ->
        case Observatory.Fleet.AgentProcess.resume(input.arguments.agent_id) do
          :ok -> {:ok, %{agent_id: input.arguments.agent_id, status: :active}}
          error -> {:error, "Failed to resume: #{inspect(error)}"}
        end
      end
    end

    action :terminate_agent, :map do
      description "Terminate an agent process."
      argument :agent_id, :string, allow_nil?: false

      run fn input, _context ->
        agent_id = input.arguments.agent_id

        case Observatory.Fleet.AgentProcess.lookup(agent_id) do
          {_pid, meta} ->
            result =
              case meta[:team] do
                nil -> Observatory.Fleet.FleetSupervisor.terminate_agent(agent_id)
                team -> Observatory.Fleet.TeamSupervisor.terminate_member(team, agent_id)
              end

            case result do
              :ok -> {:ok, %{agent_id: agent_id, status: :terminated}}
              error -> {:error, "Failed to terminate: #{inspect(error)}"}
            end

          nil ->
            {:error, "Agent not found: #{agent_id}"}
        end
      end
    end

    action :launch, :map do
      description "Launch a full agent: tmux session + Claude Code + BEAM process + instruction overlay."

      argument :name, :string, description: "Agent name (auto-generated if blank)"
      argument :capability, :string, default: "builder", description: "Role: builder, scout, reviewer, lead"
      argument :model, :string, default: "sonnet", description: "Claude model to use"
      argument :cwd, :string, description: "Working directory"
      argument :team_name, :string, description: "Team to join"
      argument :extra_instructions, :string, description: "Additional instructions for the overlay"

      run fn input, _context ->
        args = input.arguments

        opts =
          %{}
          |> maybe_put(:name, args[:name])
          |> maybe_put(:capability, args[:capability])
          |> maybe_put(:model, args[:model])
          |> maybe_put(:cwd, args[:cwd])
          |> maybe_put(:team_name, args[:team_name])
          |> maybe_put(:extra_instructions, args[:extra_instructions])

        case Observatory.AgentSpawner.spawn_agent(opts) do
          {:ok, result} ->
            {:ok, result}

          {:error, {:session_exists, session}} ->
            {:error, "Session already exists: #{session}"}

          {:error, {:cwd_not_found, path}} ->
            {:error, "Directory not found: #{path}"}

          {:error, reason} ->
            {:error, "Failed to launch agent: #{inspect(reason)}"}
        end
      end
    end

    # ── Messaging ────────────────────────────────────────────────────

    action :send_message, :map do
      description "Send a message to an agent."

      argument :agent_id, :string, allow_nil?: false, description: "Target agent ID"
      argument :content, :string, allow_nil?: false, description: "Message content"
      argument :from, :string, default: "architect", description: "Sender identifier"

      run fn input, _context ->
        args = input.arguments

        Observatory.Fleet.AgentProcess.send_message(args.agent_id, %{
          content: args.content,
          from: args.from,
          type: :message
        })

        {:ok, %{to: args.agent_id, from: args.from, status: :sent}}
      end
    end

    action :update_instructions, :map do
      description "Update an agent's instruction overlay."

      argument :agent_id, :string, allow_nil?: false
      argument :instructions, :string, allow_nil?: false

      run fn input, _context ->
        args = input.arguments
        Observatory.Fleet.AgentProcess.update_instructions(args.agent_id, args.instructions)
        {:ok, %{agent_id: args.agent_id, status: :updated}}
      end
    end
  end

  code_interface do
    # Reads
    define :all
    define :active
    define :in_team, args: [:team_name]
    # Lifecycle
    define :launch, args: []
    define :spawn, args: [:id]
    define :pause_agent, args: [:agent_id]
    define :resume_agent, args: [:agent_id]
    define :terminate_agent, args: [:agent_id]
    # Messaging
    define :send_message, args: [:agent_id, :content]
    define :update_instructions, args: [:agent_id, :instructions]
  end

  # ── Private Helpers ──────────────────────────────────────────────

  @spec spawn_in_fleet(String.t() | nil, keyword()) :: {:ok, pid()} | {:error, term()}
  defp spawn_in_fleet(nil, opts) do
    Observatory.Fleet.FleetSupervisor.spawn_agent(opts)
  end

  defp spawn_in_fleet(team_name, opts) do
    # Ensure the team exists first
    unless Observatory.Fleet.TeamSupervisor.exists?(team_name) do
      Observatory.Fleet.FleetSupervisor.create_team(name: team_name)
    end

    Observatory.Fleet.TeamSupervisor.spawn_member(team_name, opts)
  end

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
