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

      # Register in AgentRegistry with parent-child relationship
      role = capability_to_role(capability)

      Observatory.Gateway.AgentRegistry.register_spawned(agent_id,
        name: name,
        role: role,
        team: opts[:team_name],
        cwd: cwd,
        parent_id: opts[:parent_id],
        channels: %{tmux: session_name}
      )

      Logger.info("AgentSpawner: Spawned agent #{name} in session #{session_name} at #{cwd}")

      Phoenix.PubSub.broadcast(
        Observatory.PubSub,
        "agent:spawned",
        {:agent_spawned, agent_id, name, capability}
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

  @doc "Stop a spawned agent by sending /exit to its tmux session."
  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  def stop_agent(session_name) do
    case Tmux.run_command(["send-keys", "-t", session_name, "/exit", "Enter"]) do
      {_, 0} ->
        Logger.info("AgentSpawner: Sent /exit to #{session_name}")
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
