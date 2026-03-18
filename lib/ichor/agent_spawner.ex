defmodule Ichor.AgentSpawner do
  @moduledoc """
  Spawns agents as tmux windows within team sessions, with BEAM process backing.

  Tmux model: one session per team, one window per agent.
    - Team agents:    session = team_name,      window = agent_name
    - Standalone:     session = "ichor-fleet",   window = agent_name
    - MES (separate): session = "mes-{run_id}",  window = role_name

  Pipeline: validate -> write overlay -> ensure session -> create window -> start AgentProcess.
  Supports remote spawning on connected BEAM nodes via `:host` option.
  """

  require Logger

  alias Ichor.Fleet.AgentProcess
  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Fleet.HostRegistry
  alias Ichor.Fleet.TeamSupervisor
  alias Ichor.Fleet.TmuxHelpers
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.InstructionOverlay

  @ichor_socket Path.expand("~/.ichor/tmux/obs.sock")
  @counter_key :ichor_spawn_counter
  @standalone_session "ichor-fleet"

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
    window_name = unique_window_name(name)
    team_session = resolve_team_session(opts[:team_name])

    with :ok <- validate_cwd(cwd),
         :ok <- validate_no_window_conflict(team_session, window_name),
         :ok <- InstructionOverlay.write_session_files(cwd, opts),
         :ok <- ensure_session(team_session, cwd),
         {:ok, _} <- create_window(team_session, window_name, cwd, opts) do
      tmux_target = "#{team_session}:#{window_name}"
      register_agent(tmux_target, window_name, name, cwd, opts)
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
  def spawned_session?(@standalone_session), do: true

  def spawned_session?("ichor-" <> rest) do
    case String.split(rest, "-") do
      [n] -> integer?(n)
      [_team_hash, _n] -> true
      _ -> false
    end
  end

  def spawned_session?(_), do: false

  @doc "Stop a spawned agent by terminating its BEAM process and sending /exit to tmux."
  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  def stop_agent(agent_id) do
    # Look up tmux_target from Registry metadata before terminating
    tmux_target = resolve_tmux_target(agent_id)
    terminate_beam_process(agent_id)
    send_tmux_exit(tmux_target || agent_id)
    Ichor.EventBuffer.remove_session(agent_id)
  end

  # ── Private: Session & Window Naming ─────────────────────────────────

  defp resolve_team_session(nil), do: @standalone_session
  defp resolve_team_session(team_name), do: team_name

  defp unique_window_name(name) do
    "#{name}-#{next_counter()}"
  end

  defp next_counter do
    ref = :persistent_term.get(@counter_key)
    :atomics.add_get(ref, 1, 1)
  end

  defp integer?(str), do: match?({_, ""}, Integer.parse(str))

  # ── Private: Spawn Pipeline ────────────────────────────────────────

  defp spawn_remote(node, opts) do
    Logger.info("[AgentSpawner] Spawning on remote node #{node}")

    case :rpc.call(node, __MODULE__, :spawn_local, [opts]) do
      {:badrpc, reason} ->
        {:error, {:remote_spawn_failed, node, reason}}

      {:ok, result} ->
        {:ok, Map.put(result, :node, node)}

      {:error, _} = error ->
        error
    end
  end

  defp register_agent(tmux_target, agent_id, name, cwd, opts) do
    capability = opts[:capability] || "builder"
    role = TmuxHelpers.capability_to_role(capability)

    process_opts = [
      id: agent_id,
      role: role,
      team: opts[:team_name],
      liveness_poll: true,
      backend: %{type: :tmux, session: tmux_target},
      capabilities: TmuxHelpers.capabilities_for(capability),
      metadata: %{cwd: cwd, model: opts[:model] || "sonnet", parent_id: opts[:parent_id]}
    ]

    start_agent_process(process_opts, opts[:team_name], name, cwd)

    {:ok,
     %{
       session_name: tmux_target,
       agent_id: agent_id,
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
    TmuxHelpers.ensure_team(team_name)

    case TeamSupervisor.spawn_member(team_name, process_opts) do
      {:ok, _pid} -> Logger.info("[AgentSpawner] Spawned #{name} in team #{team_name} at #{cwd}")
      {:error, reason} -> Logger.warning("[AgentSpawner] BEAM process failed: #{inspect(reason)}")
    end
  end

  # ── Private: Validation ────────────────────────────────────────────

  defp validate_no_window_conflict(session, window_name) do
    target = "#{session}:#{window_name}"

    case Tmux.available?(target) do
      true -> {:error, {:window_exists, target}}
      false -> :ok
    end
  end

  defp validate_cwd(cwd) do
    case File.dir?(cwd) do
      true -> :ok
      false -> {:error, {:cwd_not_found, cwd}}
    end
  end

  # ── Private: Tmux Session & Window ─────────────────────────────────

  defp ensure_session(session, cwd) do
    if Tmux.available?(session) do
      :ok
    else
      args = tmux_server_args() ++ ["new-session", "-d", "-s", session, "-c", cwd]

      case System.cmd("tmux", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, code} -> {:error, {:session_create_failed, output, code}}
      end
    end
  end

  defp create_window(session, window_name, cwd, opts) do
    command = build_command(opts)

    args =
      tmux_server_args() ++
        ["new-window", "-t", session, "-n", window_name, "-c", cwd, command]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_, 0} -> {:ok, "#{session}:#{window_name}"}
      {output, code} -> {:error, {:window_create_failed, output, code}}
    end
  end

  defp build_command(opts) do
    model = opts[:model] || "sonnet"
    capability = opts[:capability] || "builder"
    claude_args = build_claude_args(model, capability, opts)
    "env -u CLAUDECODE claude #{Enum.join(claude_args, " ")}"
  end

  defp build_claude_args(model, capability, _opts) do
    ["--model", model]
    |> TmuxHelpers.add_permission_args(capability)
  end

  defp tmux_server_args do
    case File.exists?(@ichor_socket) do
      true -> ["-S", @ichor_socket]
      false -> ["-L", "obs"]
    end
  end

  # ── Private: Stop ──────────────────────────────────────────────────

  defp resolve_tmux_target(agent_id) do
    case AgentProcess.lookup(agent_id) do
      {_pid, %{tmux_target: target}} when is_binary(target) -> target
      _ -> nil
    end
  end

  defp terminate_beam_process(agent_id) do
    case AgentProcess.alive?(agent_id) do
      false ->
        :ok

      true ->
        state = AgentProcess.get_state(agent_id)
        do_terminate(state, agent_id)
    end
  end

  defp do_terminate(%{team: nil}, agent_id), do: FleetSupervisor.terminate_agent(agent_id)

  defp do_terminate(%{team: team}, agent_id),
    do: TeamSupervisor.terminate_member(team, agent_id)

  defp send_tmux_exit(tmux_target) do
    case Tmux.run_command(["send-keys", "-t", tmux_target, "/exit", "Enter"]) do
      {_, 0} ->
        Logger.info("[AgentSpawner] Stopped #{tmux_target}")
        :ok

      {output, code} ->
        {:error, {:tmux_send_failed, output, code}}
    end
  end
end
