defmodule Ichor.Fleet.Agent do
  @moduledoc """
  An agent in the fleet. The Ash resource provides both read access (via preparations
  that load from Registry/events) and write operations (via generic actions that
  delegate to the BEAM-native GenServer layer).

  This is the canonical entry point for all agent operations.
  """

  use Ash.Resource, domain: Ichor.Fleet

  import Ichor.MapHelpers, only: [maybe_put: 3]

  alias Ichor.AgentSpawner
  alias Ichor.Fleet.AgentProcess
  alias Ichor.Fleet.Runtime

  attributes do
    attribute(:agent_id, :string, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)
    attribute(:role, :string, public?: true)
    attribute(:model, :string, public?: true)
    attribute(:status, :atom, constraints: [one_of: [:active, :idle, :ended]], public?: true)

    attribute(:health, :atom,
      constraints: [one_of: [:healthy, :warning, :critical, :unknown]],
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
    # ── Reads ────────────────────────────────────────────────────────

    read :all do
      prepare({Ichor.Fleet.Views.Preparations.LoadAgents, []})
    end

    read :active do
      prepare({Ichor.Fleet.Views.Preparations.LoadAgents, []})
      filter(expr(status != :ended))
    end

    read :in_team do
      argument(:team_name, :string, allow_nil?: false)
      prepare({Ichor.Fleet.Views.Preparations.LoadAgents, []})
      filter(expr(team_name == ^arg(:team_name)))
    end

    # ── Lifecycle ────────────────────────────────────────────────────

    action :spawn, :map do
      description("Spawn a new agent process in the fleet.")

      argument(:id, :string, allow_nil?: false, description: "Unique agent identifier")
      argument(:role, :atom, default: :worker, description: "Agent role")
      argument(:team_name, :string, description: "Team to join (nil for standalone)")
      argument(:backend, :map, description: "Backend transport config")
      argument(:capabilities, {:array, :atom}, default: [], description: "Agent capabilities")
      argument(:instructions, :string, description: "Initial instruction overlay")

      run(fn input, _context ->
        args = input.arguments
        opts = [id: args.id, role: args.role, capabilities: args.capabilities]

        opts =
          if args[:instructions],
            do: Keyword.put(opts, :instructions, args.instructions),
            else: opts

        opts = if args[:backend], do: Keyword.put(opts, :backend, args.backend), else: opts

        case spawn_in_fleet(args[:team_name], opts) do
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

        case AgentProcess.lookup(agent_id) do
          {_pid, meta} ->
            result =
              case meta[:team] do
                nil -> Runtime.terminate_standalone_agent(agent_id)
                team -> Runtime.terminate_team_member(team, agent_id)
              end

            case result do
              :ok -> {:ok, %{agent_id: agent_id, status: :terminated}}
              error -> {:error, "Failed to terminate: #{inspect(error)}"}
            end

          nil ->
            {:error, "Agent not found: #{agent_id}"}
        end
      end)
    end

    action :launch, :map do
      description(
        "Launch a full agent: tmux session + Claude Code + BEAM process + instruction overlay."
      )

      argument(:name, :string, description: "Agent name (auto-generated if blank)")

      argument(:capability, :string,
        default: "builder",
        description: "Role: builder, scout, reviewer, lead"
      )

      argument(:model, :string, default: "sonnet", description: "Claude model to use")
      argument(:cwd, :string, description: "Working directory")
      argument(:team_name, :string, description: "Team to join")

      argument(:extra_instructions, :string,
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

        case AgentSpawner.spawn_agent(opts) do
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

    # ── Messaging ────────────────────────────────────────────────────

    action :send_message, :map do
      description("Send a message to an agent.")

      argument(:agent_id, :string, allow_nil?: false, description: "Target agent ID")
      argument(:content, :string, allow_nil?: false, description: "Message content")
      argument(:from, :string, default: "architect", description: "Sender identifier")

      run(fn input, _context ->
        args = input.arguments

        AgentProcess.send_message(args.agent_id, %{
          content: args.content,
          from: args.from,
          type: :message
        })

        {:ok, %{to: args.agent_id, from: args.from, status: :sent}}
      end)
    end

    action :get_unread, {:array, :map} do
      description("Get unread messages for an agent.")
      argument(:agent_id, :string, allow_nil?: false, description: "Agent session ID")

      run(fn input, _context ->
        agent_id = input.arguments.agent_id

        messages =
          if AgentProcess.alive?(agent_id) do
            AgentProcess.get_unread(agent_id)
            |> Enum.map(fn msg ->
              %{
                "id" => msg[:id] || Ecto.UUID.generate(),
                "from" => msg[:from] || "system",
                "content" => msg[:content] || inspect(msg),
                "type" => to_string(msg[:type] || :message),
                "timestamp" => DateTime.to_iso8601(msg[:timestamp] || DateTime.utc_now())
              }
            end)
          else
            []
          end

        {:ok, messages}
      end)
    end

    action :mark_read, :map do
      description("Mark a message as read for an agent.")
      argument(:agent_id, :string, allow_nil?: false)
      argument(:message_id, :string, allow_nil?: false)

      run(fn input, _context ->
        # AgentProcess.get_unread is a destructive read (clears on read).
        # mark_read is a no-op -- messages are consumed when read.
        {:ok, %{status: "acknowledged", message_id: input.arguments.message_id}}
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
    # Lifecycle
    define(:launch, args: [])
    define(:spawn, args: [:id])
    define(:pause_agent, args: [:agent_id])
    define(:resume_agent, args: [:agent_id])
    define(:terminate_agent, args: [:agent_id])
    # Messaging
    define(:get_unread, args: [:agent_id])
    define(:mark_read, args: [:agent_id, :message_id])
    define(:send_message, args: [:agent_id, :content])
    define(:update_instructions, args: [:agent_id, :instructions])
  end

  # ── Private Helpers ──────────────────────────────────────────────

  @spec spawn_in_fleet(String.t() | nil, keyword()) :: {:ok, pid()} | {:error, term()}
  defp spawn_in_fleet(nil, opts) do
    Runtime.spawn_standalone_agent(opts)
  end

  defp spawn_in_fleet(team_name, opts) do
    unless Runtime.team_exists?(team_name) do
      Runtime.create_team(name: team_name)
    end

    Runtime.spawn_team_member(team_name, opts)
  end
end
