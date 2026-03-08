defmodule Observatory.AgentSpawner do
  @moduledoc """
  Spawns Claude Code agents in isolated tmux sessions.

  Pipeline:
    1. Create tmux session via observatory socket
    2. Generate instruction overlay (CLAUDE.md) with role, task, file scope
    3. Write overlay + settings.local.json hooks to worktree
    4. Launch `claude` in the tmux session
    5. Register in AgentRegistry

  Inspired by Overstory's `ov sling` 14-step spawn pipeline.
  """
  require Logger

  alias Observatory.Gateway.Channels.Tmux

  @observatory_socket Path.expand("~/.observatory/tmux/obs.sock")

  @type spawn_opts :: %{
          optional(:name) => String.t(),
          optional(:capability) => String.t(),
          optional(:model) => String.t(),
          optional(:task) => map(),
          optional(:file_scope) => [String.t()],
          optional(:cwd) => String.t(),
          optional(:team_name) => String.t(),
          optional(:quality_gates) => [String.t()],
          optional(:extra_instructions) => String.t(),
          optional(:parent_id) => String.t()
        }

  @doc """
  Spawn a new Claude Code agent in a tmux session.

  Returns `{:ok, %{session_name: String.t(), session_id: String.t()}}` or `{:error, reason}`.
  """
  @spec spawn_agent(spawn_opts()) :: {:ok, map()} | {:error, term()}
  def spawn_agent(opts) do
    name = opts[:name] || generate_name(opts[:capability] || "agent")
    cwd = opts[:cwd] || File.cwd!()
    session_name = "obs-#{name}"

    with :ok <- validate_no_conflict(session_name),
         :ok <- ensure_cwd(cwd),
         :ok <- write_overlay(cwd, opts),
         {:ok, _pid} <- create_tmux_session(session_name, cwd, opts) do
      agent_id = session_name
      capability = opts[:capability] || "builder"
      role = capability_to_role(capability)

      # Start a BEAM-native AgentProcess backed by the tmux session
      process_opts = [
        id: agent_id,
        role: role,
        team: opts[:team_name],
        backend: %{type: :tmux, session: session_name},
        capabilities: capabilities_for(capability),
        metadata: %{cwd: cwd, model: opts[:model] || "sonnet", parent_id: opts[:parent_id]}
      ]

      case start_agent_process(process_opts, opts[:team_name]) do
        {:ok, _pid} ->
          Logger.info("AgentSpawner: Spawned agent #{name} (BEAM process + tmux) at #{cwd}")

        {:error, reason} ->
          Logger.warning("AgentSpawner: BEAM process failed (#{inspect(reason)}), tmux-only for #{name}")
      end

      # Also register in legacy AgentRegistry for backward compatibility
      Observatory.Gateway.AgentRegistry.register_spawned(agent_id,
        name: name,
        role: role,
        team: opts[:team_name],
        cwd: cwd,
        parent_id: opts[:parent_id],
        channels: %{tmux: session_name}
      )

      {:ok, %{session_name: session_name, agent_id: agent_id, name: name, cwd: cwd}}
    end
  end

  @doc "List all observatory-spawned agent sessions."
  @spec list_spawned() :: [String.t()]
  def list_spawned do
    Tmux.list_sessions()
    |> Enum.filter(&String.starts_with?(&1, "obs-"))
  end

  @doc "Stop a spawned agent by sending /exit to its tmux session and terminating its BEAM process."
  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  def stop_agent(session_name) do
    # Terminate the BEAM process if it exists
    if Observatory.Fleet.AgentProcess.alive?(session_name) do
      state = Observatory.Fleet.AgentProcess.get_state(session_name)

      if state.team do
        Observatory.Fleet.TeamSupervisor.terminate_member(state.team, session_name)
      else
        Observatory.Fleet.FleetSupervisor.terminate_agent(session_name)
      end
    end

    # Send /exit to the tmux session
    case Tmux.run_command(["send-keys", "-t", session_name, "/exit", "Enter"]) do
      {_, 0} ->
        Logger.info("AgentSpawner: Stopped #{session_name}")
        :ok

      {output, code} ->
        {:error, {:tmux_send_failed, output, code}}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp validate_no_conflict(session_name) do
    if Tmux.available?(session_name) do
      {:error, {:session_exists, session_name}}
    else
      :ok
    end
  end

  defp ensure_cwd(cwd) do
    if File.dir?(cwd), do: :ok, else: {:error, {:cwd_not_found, cwd}}
  end

  defp write_overlay(cwd, opts) do
    overlay_content = Observatory.InstructionOverlay.generate(opts)
    overlay_path = Path.join(cwd, ".claude/OBSERVATORY_OVERLAY.md")

    File.mkdir_p!(Path.dirname(overlay_path))
    File.write!(overlay_path, overlay_content)

    # Write hooks that point back to Observatory
    write_hooks(cwd, opts)

    :ok
  end

  defp write_hooks(cwd, opts) do
    settings_path = Path.join(cwd, ".claude/settings.local.json")

    port = Application.get_env(:observatory, ObservatoryWeb.Endpoint, [])
           |> get_in([:http, :port]) || 4005

    agent_name = opts[:name] || "agent"

    hooks = %{
      "hooks" => %{
        "PostToolUse" => [
          %{
            "matcher" => "",
            "hooks" => [
              %{
                "type" => "command",
                "command" => "curl -s -X POST http://localhost:#{port}/api/events -H 'Content-Type: application/json' -d '{\"event_type\": \"PostToolUse\", \"agent_name\": \"#{agent_name}\"}' > /dev/null 2>&1 || true"
              }
            ]
          }
        ]
      }
    }

    # Merge with existing settings if present
    existing =
      case File.read(settings_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, map} -> map
            _ -> %{}
          end
        _ -> %{}
      end

    merged = Map.merge(existing, hooks)

    case Jason.encode(merged, pretty: true) do
      {:ok, json} -> File.write!(settings_path, json)
      _ -> :ok
    end
  end

  defp create_tmux_session(session_name, cwd, opts) do
    model = opts[:model] || "sonnet"
    capability = opts[:capability] || "builder"

    # Build claude command with appropriate flags
    claude_args = build_claude_args(model, capability, cwd, opts)
    command = "claude #{Enum.join(claude_args, " ")}"

    server_args = tmux_server_args()

    args =
      server_args ++
        ["new-session", "-d", "-s", session_name, "-c", cwd, command]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_, 0} ->
        {:ok, session_name}

      {output, code} ->
        Logger.error("AgentSpawner: Failed to create tmux session: #{output}")
        {:error, {:tmux_create_failed, output, code}}
    end
  end

  defp build_claude_args(model, capability, _cwd, opts) do
    args = ["--model", model]

    # Set permission mode based on capability
    args =
      case capability do
        cap when cap in ["builder", "lead"] -> args ++ ["--dangerously-skip-permissions"]
        "scout" -> args ++ ["--allowedTools", "Read,Glob,Grep,Bash(read-only)"]
        _ -> args
      end

    # Add initial prompt if task provided
    args =
      if opts[:task] do
        task = opts[:task]
        prompt = "Work on task: #{task["subject"] || task[:subject]}. #{task["description"] || task[:description] || ""}"
        args ++ ["-p", "\"#{prompt}\""]
      else
        args
      end

    args
  end

  defp tmux_server_args do
    if File.exists?(@observatory_socket) do
      ["-S", @observatory_socket]
    else
      ["-L", "obs"]
    end
  end

  defp start_agent_process(process_opts, nil) do
    # Standalone agent -- direct child of FleetSupervisor
    Observatory.Fleet.FleetSupervisor.spawn_agent(process_opts)
  end

  defp start_agent_process(process_opts, team_name) do
    # Team member -- ensure team exists, then spawn under it
    unless Observatory.Fleet.TeamSupervisor.exists?(team_name) do
      Observatory.Fleet.FleetSupervisor.create_team(name: team_name)
    end

    Observatory.Fleet.TeamSupervisor.spawn_member(team_name, process_opts)
  end

  defp capabilities_for("lead"), do: [:read, :write, :spawn, :assign, :escalate]
  defp capabilities_for("coordinator"), do: [:read, :write, :spawn, :assign, :escalate, :kill]
  defp capabilities_for("scout"), do: [:read]
  defp capabilities_for("reviewer"), do: [:read, :write]
  defp capabilities_for("builder"), do: [:read, :write]
  defp capabilities_for(_), do: [:read, :write]

  defp capability_to_role("lead"), do: :lead
  defp capability_to_role("coordinator"), do: :coordinator
  defp capability_to_role("scout"), do: :worker
  defp capability_to_role("reviewer"), do: :worker
  defp capability_to_role("builder"), do: :worker
  defp capability_to_role(_), do: :worker

  defp generate_name(capability) do
    suffix = :rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")
    "#{capability}-#{suffix}"
  end
end
