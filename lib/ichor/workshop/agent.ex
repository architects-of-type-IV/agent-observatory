defmodule Ichor.Workshop.Agent do
  @moduledoc """
  An agent in the fleet. The Ash resource provides both read access (via preparations
  that load from Registry/events) and write operations (via generic actions that
  delegate to the BEAM-native GenServer layer).

  This is the canonical entry point for all agent operations.
  """

  import Ichor.Util, only: [maybe_put: 3]

  use Ash.Resource, domain: Ichor.Workshop

  alias Ichor.Infrastructure.AgentLaunch
  alias Ichor.Infrastructure.AgentProcess
  alias Ichor.Infrastructure.Registration
  alias Ichor.Infrastructure.Tmux
  alias Ichor.Workshop.AgentLookup

  attributes do
    attribute(:agent_id, :string, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)
    attribute(:role, :string, public?: true)
    attribute(:model, :string, public?: true)

    attribute :status, :atom do
      constraints(one_of: [:active, :idle, :ended])
      public?(true)
    end

    attribute(:health, Ichor.Workshop.Types.HealthStatus,
      default: :unknown,
      public?: true
    )

    attribute(:current_tool, :map, public?: true)
    attribute(:event_count, :integer, default: 0, public?: true)
    attribute(:tool_count, :integer, default: 0, public?: true)
    attribute(:cwd, :string, public?: true)
    attribute(:source_app, :string, public?: true)
    attribute(:project, :string, public?: true)
    attribute(:health_issues, {:array, :map}, default: [], public?: true)
    attribute(:team_name, :string, public?: true)
    attribute(:tmux_session, :string, public?: true)
    attribute(:recent_activity, {:array, :map}, default: [], public?: true)
    attribute(:session_id, :string, public?: true)
    attribute(:short_name, :string, public?: true)
    attribute(:host, :string, default: "local", public?: true)
    attribute(:channels, :map, default: %{}, public?: true)
    attribute(:last_event_at, :utc_datetime_usec, public?: true)
    attribute(:os_pid, :integer, public?: true)
    attribute(:subagents, {:array, :map}, default: [], public?: true)
  end

  actions do
    read :all do
      description("Load all agents currently registered in the fleet, including ended sessions.")
      prepare({Ichor.Workshop.Preparations.LoadAgents, []})
    end

    read :active do
      description("Load all agents with an active or idle status, excluding ended sessions.")
      prepare({Ichor.Workshop.Preparations.LoadAgents, []})
      filter(expr(status != :ended))
    end

    read :in_team do
      description("Load all agents belonging to a specific named team.")
      argument(:team_name, :string, allow_nil?: false)
      prepare({Ichor.Workshop.Preparations.LoadAgents, []})
      filter(expr(team_name == ^arg(:team_name)))
    end

    action :list_live_agents, {:array, :map} do
      description("List all live agents with their current runtime status.")

      run(fn _input, _context ->
        case __MODULE__ |> Ash.Query.for_read(:active) |> Ash.read() do
          {:ok, agents} ->
            {:ok,
             Enum.map(agents, fn agent ->
               %{
                 "id" => agent.agent_id,
                 "name" => agent.short_name || agent.name || agent.agent_id,
                 "session_id" => agent.session_id,
                 "team" => agent.team_name,
                 "role" => agent.role,
                 "status" => agent.status,
                 "model" => agent.model,
                 "cwd" => agent.cwd,
                 "current_tool" => agent.current_tool,
                 "last_event_at" => agent.last_event_at
               }
             end)}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end

    action :agent_status, :map do
      description("Get detailed runtime status for a specific agent by name or session ID.")

      argument(:agent_id, :string, allow_nil?: false)

      run(fn input, _context ->
        query = input.arguments.agent_id

        case AgentLookup.find_agent(query) do
          nil ->
            {:ok, %{"found" => false, "query" => query}}

          agent ->
            tmux_target = agent.channels[:tmux] || agent.tmux_session

            tmux_ok =
              if is_binary(tmux_target),
                do: Tmux.available?(tmux_target),
                else: false

            {:ok,
             %{
               "id" => agent.agent_id,
               "name" => agent.short_name || agent.name || agent.agent_id,
               "session_id" => agent.session_id,
               "team" => agent.team_name,
               "role" => agent.role,
               "status" => agent.status,
               "model" => agent.model,
               "cwd" => agent.cwd,
               "current_tool" => agent.current_tool,
               "last_event_at" => agent.last_event_at,
               "found" => true,
               "tmux" => tmux_target,
               "tmux_available" => tmux_ok
             }}
        end
      end)
    end

    action :spawn, :map do
      description("Spawn a new agent process in the fleet.")

      argument(:id, :string, allow_nil?: false, description: "Unique agent identifier")
      argument(:role, :atom, default: :worker, description: "Agent role")

      argument(:team_name, :string,
        allow_nil?: false,
        default: "",
        description: "Team to join (nil for standalone)"
      )

      argument(:backend, :map,
        allow_nil?: false,
        default: %{},
        description: "Backend transport config"
      )

      argument(:capabilities, {:array, :atom}, default: [], description: "Agent capabilities")

      argument(:instructions, :string,
        allow_nil?: false,
        default: "",
        description: "Initial instruction overlay"
      )

      run(fn input, _context ->
        args = input.arguments

        opts =
          [id: args.id, role: args.role, capabilities: args.capabilities]
          |> then(fn o ->
            if args[:instructions], do: Keyword.put(o, :instructions, args.instructions), else: o
          end)
          |> then(fn o ->
            if args[:backend], do: Keyword.put(o, :backend, args.backend), else: o
          end)

        case AgentLookup.spawn_in_fleet(args[:team_name], opts) do
          {:ok, pid} ->
            {:ok, %{agent_id: args.id, pid: inspect(pid), status: :active}}

          {:error, {:already_started, pid}} ->
            {:ok,
             %{agent_id: args.id, pid: inspect(pid), status: :active, note: "already running"}}

          {:error, reason} ->
            {:error, "Failed to spawn agent: #{inspect(reason)}"}
        end
      end)
    end

    action :pause_agent, :map do
      description("Pause an agent (buffers messages, stops backend delivery).")
      argument(:agent_id, :string, allow_nil?: false)

      run(fn input, _context ->
        case AgentProcess.pause(input.arguments.agent_id) do
          :ok -> {:ok, %{agent_id: input.arguments.agent_id, status: :paused}}
          error -> {:error, "Failed to pause: #{inspect(error)}"}
        end
      end)
    end

    action :resume_agent, :map do
      description("Resume a paused agent (delivers buffered messages).")
      argument(:agent_id, :string, allow_nil?: false)

      run(fn input, _context ->
        case AgentProcess.resume(input.arguments.agent_id) do
          :ok -> {:ok, %{agent_id: input.arguments.agent_id, status: :active}}
          error -> {:error, "Failed to resume: #{inspect(error)}"}
        end
      end)
    end

    action :terminate_agent, :map do
      description("Terminate an agent process.")
      argument(:agent_id, :string, allow_nil?: false)

      run(fn input, _context ->
        agent_id = input.arguments.agent_id

        case Registration.terminate(agent_id) do
          :ok -> {:ok, %{agent_id: agent_id, status: :terminated}}
          {:error, :not_found} -> {:error, "Agent not found: #{agent_id}"}
          error -> {:error, "Failed to terminate: #{inspect(error)}"}
        end
      end)
    end

    action :launch, :map do
      description(
        "Launch a full agent: tmux session + Claude Code + BEAM process + instruction overlay."
      )

      argument(:name, :string,
        allow_nil?: false,
        default: "",
        description: "Agent name (auto-generated if blank)"
      )

      argument(:capability, :string,
        default: "builder",
        description: "Role: builder, scout, reviewer, lead"
      )

      argument(:model, :string, default: "sonnet", description: "Claude model to use")

      argument(:cwd, :string,
        allow_nil?: false,
        default: "",
        description: "Working directory"
      )

      argument(:team_name, :string,
        allow_nil?: false,
        default: "",
        description: "Team to join"
      )

      argument(:extra_instructions, :string,
        allow_nil?: false,
        default: "",
        description: "Additional instructions for the overlay"
      )

      run(fn input, _context ->
        args = input.arguments

        opts =
          %{}
          |> maybe_put(:name, args[:name])
          |> maybe_put(:capability, args[:capability])
          |> maybe_put(:model, args[:model])
          |> maybe_put(:cwd, args[:cwd])
          |> maybe_put(:team_name, args[:team_name])
          |> maybe_put(:extra_instructions, args[:extra_instructions])

        case AgentLaunch.spawn(opts) do
          {:ok, result} ->
            {:ok, result}

          {:error, {:session_exists, session}} ->
            {:error, "Session already exists: #{session}"}

          {:error, {:cwd_not_found, path}} ->
            {:error, "Directory not found: #{path}"}

          {:error, reason} ->
            {:error, "Failed to launch agent: #{inspect(reason)}"}
        end
      end)
    end

    action :spawn_agent, :map do
      description("Spawn a new agent in tmux with full fleet observability.")

      argument(:prompt, :string, allow_nil?: false)
      argument(:capability, :string, allow_nil?: false, default: "builder")
      argument(:model, :string, allow_nil?: false, default: "sonnet")
      argument(:name, :string, allow_nil?: false, default: "")
      argument(:team_name, :string, allow_nil?: false, default: "")
      argument(:cwd, :string, allow_nil?: false, default: "")
      argument(:file_scope, {:array, :string}, allow_nil?: false, default: [])
      argument(:extra_instructions, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        opts =
          %{capability: args[:capability] || "builder", model: args[:model] || "sonnet"}
          |> maybe_put(:name, args[:name])
          |> maybe_put(:team_name, args[:team_name])
          |> maybe_put(:cwd, args[:cwd])
          |> maybe_put(:file_scope, args[:file_scope])
          |> maybe_put(:extra_instructions, args[:extra_instructions])
          |> Map.put(:task, %{"subject" => "Agent task", "description" => args.prompt})

        case AgentLaunch.spawn(opts) do
          {:ok, result} ->
            {:ok,
             %{
               "status" => "spawned",
               "agent_id" => result[:agent_id],
               "name" => result[:name],
               "session" => result[:session_name],
               "cwd" => result[:cwd],
               "team" => args[:team_name],
               "model" => args[:model] || "sonnet"
             }}

          {:error, {:session_exists, session}} ->
            {:error, "Session already exists: #{session}. Choose a different name."}

          {:error, {:cwd_not_found, path}} ->
            {:error, "Directory not found: #{path}"}

          {:error, reason} ->
            {:error, "Spawn failed: #{inspect(reason)}"}
        end
      end)
    end

    action :spawn_archon_agent, :map do
      description("Spawn a new agent from Archon control surfaces.")

      argument(:prompt, :string, allow_nil?: false)
      argument(:name, :string, allow_nil?: false, default: "")
      argument(:capability, :string, allow_nil?: false, default: "builder")
      argument(:model, :string, allow_nil?: false, default: "sonnet")
      argument(:team_name, :string, allow_nil?: false, default: "")
      argument(:cwd, :string, allow_nil?: false, default: "")
      argument(:extra_instructions, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        case AgentLaunch.spawn(input.arguments) do
          {:ok, result} ->
            {:ok,
             %{
               "session_id" => result[:agent_id] || result[:session_name],
               "session_name" => result[:session_name],
               "name" => result[:name],
               "team" => result[:team_name]
             }}

          {:error, reason} ->
            {:error, inspect(reason)}
        end
      end)
    end

    action :stop_agent, :map do
      description("Stop an agent by name or session ID.")

      argument(:agent_id, :string, allow_nil?: false)

      run(fn input, _context ->
        case AgentLookup.find_agent(input.arguments.agent_id) do
          nil ->
            {:error, "agent not found: #{input.arguments.agent_id}"}

          agent ->
            agent_id = agent.tmux_session || agent.agent_id
            _ = AgentLaunch.stop(agent_id)
            {:ok, %{"stopped" => true, "session" => agent_id, "name" => agent.name}}
        end
      end)
    end

    action :update_instructions, :map do
      description("Update an agent's instruction overlay.")

      argument(:agent_id, :string, allow_nil?: false)
      argument(:instructions, :string, allow_nil?: false)

      run(fn input, _context ->
        args = input.arguments
        AgentProcess.update_instructions(args.agent_id, args.instructions)
        {:ok, %{agent_id: args.agent_id, status: :updated}}
      end)
    end
  end

  code_interface do
    # Reads
    define(:all)
    define(:active)
    define(:in_team, args: [:team_name])
    define(:list_live_agents)
    define(:agent_status, args: [:agent_id])
    # Lifecycle
    define(:launch, args: [])
    define(:spawn_agent, args: [:prompt])

    define(:spawn_archon_agent,
      args: [:prompt, :name, :capability, :model, :team_name, :cwd, :extra_instructions]
    )

    define(:spawn, args: [:id])
    define(:pause_agent, args: [:agent_id])
    define(:resume_agent, args: [:agent_id])
    define(:stop_agent, args: [:agent_id])
    define(:terminate_agent, args: [:agent_id])
    define(:update_instructions, args: [:agent_id, :instructions])
  end
end
