defmodule Ichor.AgentSpawner do
  @moduledoc """
  Spawns agents in isolated tmux sessions with BEAM process backing.

  Session naming: `ichor-{team_hash}-{n}` (team) or `ichor-{n}` (standalone).
  Counter is global and monotonic. Human-readable names live in registry metadata.

  Pipeline: validate -> write overlay -> create tmux session -> start AgentProcess.
  Supports remote spawning on connected BEAM nodes via `:host` option.
  """

  require Logger

  alias Ichor.Fleet.AgentProcess
  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Fleet.HostRegistry
  alias Ichor.Fleet.TeamSupervisor
  alias Ichor.Gateway.AgentRegistry
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.InstructionOverlay

  @ichor_socket Path.expand("~/.ichor/tmux/obs.sock")
  @counter_key :ichor_spawn_counter
  @prefix "ichor"

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
          optional(:parent_id) => String.t(),
          optional(:host) => node()
        }

  # ── Public API ──────────────────────────────────────────────────────

  @doc "Initialize the spawn counter. Called from Application.start/2."
  @spec init_counter() :: :ok
  def init_counter do
    ref = :atomics.new(1, signed: false)
    :persistent_term.put(@counter_key, ref)
    :ok
  end

  @doc "Spawn a new agent. Routes to local or remote node based on `:host` option."
  @spec spawn_agent(spawn_opts()) :: {:ok, map()} | {:error, term()}
  def spawn_agent(%{host: target} = opts) when target != nil do
    case HostRegistry.available?(target) do
      true -> spawn_remote(target, opts)
      false -> {:error, {:host_unavailable, target}}
    end
  end

  def spawn_agent(opts), do: spawn_local(opts)

  @doc false
  def spawn_local(opts) do
    name = opts[:name] || opts[:capability] || "agent"
    cwd = opts[:cwd] || File.cwd!()
    session_name = generate_session_name(opts[:team_name])

    with :ok <- validate_no_conflict(session_name),
         :ok <- validate_cwd(cwd),
         :ok <- InstructionOverlay.write_session_files(cwd, opts),
         {:ok, _} <- create_tmux_session(session_name, cwd, opts) do
      register_agent(session_name, name, cwd, opts)
    end
  end

  @doc "List all ichor-spawned agent sessions."
  @spec list_spawned() :: [String.t()]
  def list_spawned do
    Tmux.list_sessions()
    |> Enum.filter(&spawned_session?/1)
  end

  @doc "Returns true if the session name was created by the spawner."
  @spec spawned_session?(String.t()) :: boolean()
  def spawned_session?(@prefix <> "-" <> rest) do
    case String.split(rest, "-") do
      [n] -> integer?(n)
      [_team_hash, _n] -> true
      _ -> false
    end
  end

  def spawned_session?(_), do: false

  @doc "Stop a spawned agent by terminating its BEAM process and sending /exit to tmux."
  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  def stop_agent(session_name) do
    terminate_beam_process(session_name)
    send_tmux_exit(session_name)
    AgentRegistry.remove(session_name)
    Ichor.EventBuffer.remove_session(session_name)
  end

  # ── Private: Session Naming ─────────────────────────────────────────

  defp generate_session_name(nil) do
    "#{@prefix}-#{next_counter()}"
  end

  defp generate_session_name(team_name) do
    "#{@prefix}-#{team_hash(team_name)}-#{next_counter()}"
  end

  defp next_counter do
    ref = :persistent_term.get(@counter_key)
    :atomics.add_get(ref, 1, 1)
  end

  defp team_hash(name) do
    :crypto.hash(:md5, name)
    |> binary_part(0, 2)
    |> Base.encode16(case: :lower)
  end

  defp integer?(str), do: match?({_, ""}, Integer.parse(str))

  # ── Private: Spawn Pipeline ────────────────────────────────────────

  defp spawn_remote(node, opts) do
    Logger.info("[AgentSpawner] Spawning on remote node #{node}")

    case :rpc.call(node, __MODULE__, :spawn_local, [opts]) do
      {:badrpc, reason} ->
        {:error, {:remote_spawn_failed, node, reason}}

      {:ok, result} ->
        host = node_to_host(node)

        AgentRegistry.register_spawned(result.agent_id,
          name: result.name,
          role: capability_to_role(opts[:capability] || "builder"),
          team: opts[:team_name],
          cwd: result.cwd,
          parent_id: opts[:parent_id],
          host: Atom.to_string(node),
          channels: %{ssh_tmux: "#{result.session_name}@#{host}"}
        )

        {:ok, Map.put(result, :node, node)}

      {:error, _} = error ->
        error
    end
  end

  defp register_agent(session_name, name, cwd, opts) do
    capability = opts[:capability] || "builder"
    role = capability_to_role(capability)

    process_opts = [
      id: session_name,
      role: role,
      team: opts[:team_name],
      backend: %{type: :tmux, session: session_name},
      capabilities: capabilities_for(capability),
      metadata: %{cwd: cwd, model: opts[:model] || "sonnet", parent_id: opts[:parent_id]}
    ]

    start_agent_process(process_opts, opts[:team_name], name, cwd)

    {:ok,
     %{
       session_name: session_name,
       agent_id: session_name,
       name: name,
       cwd: cwd,
       node: Node.self()
     }}
  end

  defp start_agent_process(process_opts, nil, name, cwd) do
    case FleetSupervisor.spawn_agent(process_opts) do
      {:ok, _pid} -> Logger.info("[AgentSpawner] Spawned #{name} (BEAM + tmux) at #{cwd}")
      {:error, reason} -> Logger.warning("[AgentSpawner] BEAM process failed: #{inspect(reason)}")
    end
  end

  defp start_agent_process(process_opts, team_name, name, cwd) do
    ensure_team(team_name)

    case TeamSupervisor.spawn_member(team_name, process_opts) do
      {:ok, _pid} -> Logger.info("[AgentSpawner] Spawned #{name} in team #{team_name} at #{cwd}")
      {:error, reason} -> Logger.warning("[AgentSpawner] BEAM process failed: #{inspect(reason)}")
    end
  end

  defp ensure_team(name) do
    case TeamSupervisor.exists?(name) do
      true -> :ok
      false -> FleetSupervisor.create_team(name: name)
    end
  end

  # ── Private: Validation ────────────────────────────────────────────

  defp validate_no_conflict(session_name) do
    case Tmux.available?(session_name) do
      true -> {:error, {:session_exists, session_name}}
      false -> :ok
    end
  end

  defp validate_cwd(cwd) do
    case File.dir?(cwd) do
      true -> :ok
      false -> {:error, {:cwd_not_found, cwd}}
    end
  end

  # ── Private: Tmux Session ─────────────────────────────────────────

  defp create_tmux_session(session_name, cwd, opts) do
    command = build_command(opts)
    args = tmux_server_args() ++ ["new-session", "-d", "-s", session_name, "-c", cwd, command]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_, 0} -> {:ok, session_name}
      {output, code} -> {:error, {:tmux_create_failed, output, code}}
    end
  end

  defp build_command(opts) do
    model = opts[:model] || "sonnet"
    capability = opts[:capability] || "builder"
    claude_args = build_claude_args(model, capability, opts)
    "env -u CLAUDECODE claude #{Enum.join(claude_args, " ")}"
  end

  defp build_claude_args(model, capability, opts) do
    ["--model", model]
    |> add_permission_args(capability)
    |> add_task_args(opts[:task])
  end

  defp add_permission_args(args, cap) when cap in ["builder", "lead"],
    do: args ++ ["--dangerously-skip-permissions"]

  defp add_permission_args(args, "scout"),
    do: args ++ ["--allowedTools", "Read,Glob,Grep,Bash(read-only)"]

  defp add_permission_args(args, _), do: args

  defp add_task_args(args, nil), do: args

  defp add_task_args(args, task) do
    subject = task["subject"] || task[:subject]
    description = task["description"] || task[:description] || ""
    args ++ ["-p", "\"Work on task: #{subject}. #{description}\""]
  end

  defp tmux_server_args do
    case File.exists?(@ichor_socket) do
      true -> ["-S", @ichor_socket]
      false -> ["-L", "obs"]
    end
  end

  # ── Private: Stop ──────────────────────────────────────────────────

  defp terminate_beam_process(session_name) do
    case AgentProcess.alive?(session_name) do
      false ->
        :ok

      true ->
        state = AgentProcess.get_state(session_name)
        do_terminate(state, session_name)
    end
  end

  defp do_terminate(%{team: nil}, session_name), do: FleetSupervisor.terminate_agent(session_name)

  defp do_terminate(%{team: team}, session_name),
    do: TeamSupervisor.terminate_member(team, session_name)

  defp send_tmux_exit(session_name) do
    case Tmux.run_command(["send-keys", "-t", session_name, "/exit", "Enter"]) do
      {_, 0} ->
        Logger.info("[AgentSpawner] Stopped #{session_name}")
        :ok

      {output, code} ->
        {:error, {:tmux_send_failed, output, code}}
    end
  end

  # ── Private: Role Mapping ──────────────────────────────────────────

  defp capabilities_for("lead"), do: [:read, :write, :spawn, :assign, :escalate]
  defp capabilities_for("coordinator"), do: [:read, :write, :spawn, :assign, :escalate, :kill]
  defp capabilities_for("scout"), do: [:read]
  defp capabilities_for(_), do: [:read, :write]

  defp capability_to_role("lead"), do: :lead
  defp capability_to_role("coordinator"), do: :coordinator
  defp capability_to_role(_), do: :worker

  defp node_to_host(node) do
    node |> Atom.to_string() |> String.split("@") |> List.last()
  end
end
