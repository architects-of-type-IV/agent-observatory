defmodule Ichor.Mes.TeamSpawner do
  @moduledoc """
  Spawns a 5-agent MES team inside a single tmux session.

  Flow:
    1. Write per-agent prompt files to ~/.ichor/mes/{run_id}/
    2. Create one tmux session: `mes-{run_id}`
    3. Launch Claude in each window with its prompt file piped via stdin
    4. Register each agent in BEAM fleet (AgentProcess under TeamSupervisor)
    5. Return session name so Scheduler can set a kill timer

  All agents start in the observatory project root so they have access to
  the MCP server config (.mcp.json). Communication between agents flows
  through the Ichor app via send_message/check_inbox MCP tools.
  """

  alias Ichor.Fleet.{FleetSupervisor, TeamSupervisor}
  alias Ichor.Signals

  @prompt_dir Path.expand("~/.ichor/mes")
  @ichor_socket Path.expand("~/.ichor/tmux/obs.sock")

  # ── Public API ──────────────────────────────────────────────────────

  @spec spawn_run(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def spawn_run(run_id, team_name) do
    cwd = project_root()
    session = "mes-#{run_id}"
    roster = team_roster(session)

    agents = [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt: coordinator_prompt(run_id, roster)
      },
      %{name: "lead", capability: "lead", prompt: lead_prompt(run_id, roster)},
      %{name: "planner", capability: "builder", prompt: planner_prompt(run_id, roster)},
      %{name: "researcher-1", capability: "scout", prompt: researcher_prompt(run_id, 1, roster)},
      %{name: "researcher-2", capability: "scout", prompt: researcher_prompt(run_id, 2, roster)}
    ]

    with :ok <- write_agent_scripts(run_id, agents),
         :ok <- ensure_team(team_name),
         :ok <- create_session_with_agent(session, cwd, run_id, hd(agents)),
         :ok <- create_remaining_windows(session, cwd, run_id, tl(agents)) do
      Enum.each(agents, &register_agent(session, &1, team_name, run_id, cwd))
      Signals.emit(:mes_team_ready, %{session: session, agent_count: length(agents)})
      {:ok, session}
    else
      {:error, reason} ->
        Signals.emit(:mes_team_spawn_failed, %{session: session, reason: inspect(reason)})
        {:error, reason}
    end
  end

  @spec kill_session(String.t()) :: :ok
  def kill_session(session) do
    Signals.emit(:mes_team_killed, %{session: session})
    kill_args = tmux_args() ++ ["kill-session", "-t", session]
    System.cmd("tmux", kill_args, stderr_to_stdout: true)

    run_id = String.replace_prefix(session, "mes-", "")
    cleanup_prompt_files(run_id)

    :ok
  end

  @spec cleanup_old_runs() :: :ok
  def cleanup_old_runs do
    cleanup_prompt_dir()
    cleanup_orphaned_teams()
    :ok
  end

  defp cleanup_prompt_dir do
    case File.ls(@prompt_dir) do
      {:ok, dirs} ->
        Enum.each(dirs, fn dir ->
          path = Path.join(@prompt_dir, dir)

          if File.dir?(path) do
            File.rm_rf!(path)
            Signals.emit(:mes_cleanup, %{target: dir})
          end
        end)

      {:error, _} ->
        :ok
    end
  end

  @spec cleanup_orphaned_teams() :: :ok
  def cleanup_orphaned_teams do
    active_teams =
      Ichor.Mes.RunProcess.list_all()
      |> Enum.map(fn {run_id, _pid} -> "mes-#{run_id}" end)
      |> MapSet.new()

    TeamSupervisor.list_all()
    |> Enum.filter(fn {name, _meta} -> String.starts_with?(name, "mes-") end)
    |> Enum.reject(fn {name, _meta} -> MapSet.member?(active_teams, name) end)
    |> Enum.each(fn {name, _meta} ->
      FleetSupervisor.disband_team(name)
      Signals.emit(:mes_cleanup, %{target: "orphaned_team/#{name}"})
    end)

    cleanup_orphaned_tmux_sessions(active_teams)
  end

  defp cleanup_orphaned_tmux_sessions(active_teams) do
    # tmux format: \#S expands to session name
    args = tmux_args() ++ ["list-sessions", "-F", "\#S"]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.starts_with?(&1, "mes-"))
        |> Enum.reject(&MapSet.member?(active_teams, &1))
        |> Enum.each(fn session ->
          kill_args = tmux_args() ++ ["kill-session", "-t", session]
          System.cmd("tmux", kill_args, stderr_to_stdout: true)
          Signals.emit(:mes_cleanup, %{target: "orphaned_tmux/#{session}"})
        end)

      _ ->
        :ok
    end
  end

  # ── Private: Prompt Files ──────────────────────────────────────────

  defp write_agent_scripts(run_id, agents) do
    dir = prompt_dir(run_id)
    File.mkdir_p!(dir)

    Enum.each(agents, fn agent ->
      prompt_path = Path.join(dir, "#{agent.name}.txt")
      script_path = Path.join(dir, "#{agent.name}.sh")

      File.write!(prompt_path, agent.prompt)

      cli_args =
        ["--model", "sonnet"]
        |> add_permission_args(agent.capability)
        |> Enum.join(" ")

      script = "#!/bin/sh\ncat #{prompt_path} | env -u CLAUDECODE claude #{cli_args}\n"
      File.write!(script_path, script)
      File.chmod!(script_path, 0o755)
    end)

    Signals.emit(:mes_prompts_written, %{run_id: run_id, agent_count: length(agents)})
    :ok
  end

  defp prompt_dir(run_id), do: Path.join(@prompt_dir, run_id)

  defp cleanup_prompt_files(run_id) do
    dir = prompt_dir(run_id)

    if File.dir?(dir) do
      File.rm_rf!(dir)
      Signals.emit(:mes_cleanup, %{target: "prompt_files/#{run_id}"})
    end
  end

  # ── Private: Tmux Session & Windows ─────────────────────────────────

  defp create_session_with_agent(session, cwd, run_id, agent) do
    command = build_agent_command(agent, run_id)

    args =
      tmux_args() ++
        ["new-session", "-d", "-s", session, "-c", cwd, "-n", agent.name, command]

    Signals.emit(:mes_tmux_spawning, %{
      session: session,
      agent_name: agent.name,
      command: command,
      tmux_args: Enum.join(args, " ")
    })

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_, 0} ->
        Signals.emit(:mes_tmux_session_created, %{session: session, agent_name: agent.name})
        :ok

      {output, code} ->
        Signals.emit(:mes_tmux_spawn_failed, %{
          session: session,
          output: output,
          exit_code: code
        })

        {:error, {:session_create_failed, output, code}}
    end
  end

  defp create_remaining_windows(session, cwd, run_id, agents) do
    Enum.reduce_while(agents, :ok, fn agent, :ok ->
      command = build_agent_command(agent, run_id)

      args =
        tmux_args() ++
          ["new-window", "-t", session, "-n", agent.name, "-c", cwd, command]

      case System.cmd("tmux", args, stderr_to_stdout: true) do
        {_, 0} ->
          Signals.emit(:mes_tmux_window_created, %{session: session, agent_name: agent.name})
          {:cont, :ok}

        {output, code} ->
          {:halt, {:error, {:window_create_failed, agent.name, output, code}}}
      end
    end)
  end

  defp build_agent_command(agent, run_id) do
    Path.join(prompt_dir(run_id), "#{agent.name}.sh")
  end

  # ── Private: BEAM Registration ─────────────────────────────────────

  defp register_agent(session, agent, team_name, run_id, cwd) do
    agent_id = "#{session}-#{agent.name}"

    process_opts = [
      id: agent_id,
      role: capability_to_role(agent.capability),
      team: team_name,
      backend: %{type: :tmux, session: "#{session}:#{agent.name}"},
      capabilities: capabilities_for(agent.capability),
      metadata: %{cwd: cwd, model: "sonnet", mes_run: run_id}
    ]

    case TeamSupervisor.spawn_member(team_name, process_opts) do
      {:ok, _pid} ->
        Signals.emit(:mes_agent_registered, %{agent_name: agent.name, session: session})

      {:error, reason} ->
        Signals.emit(:mes_agent_register_failed, %{
          agent_name: agent.name,
          reason: inspect(reason)
        })
    end
  end

  defp ensure_team(name) do
    case TeamSupervisor.exists?(name) do
      true ->
        :ok

      false ->
        case FleetSupervisor.create_team(name: name) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, {:team_create_failed, reason}}
        end
    end
  end

  # ── Private: Role/Permission Helpers ───────────────────────────────

  defp capability_to_role("lead"), do: :lead
  defp capability_to_role("coordinator"), do: :coordinator
  defp capability_to_role(_), do: :worker

  defp capabilities_for("lead"), do: [:read, :write, :spawn, :assign, :escalate]
  defp capabilities_for("coordinator"), do: [:read, :write, :spawn, :assign, :escalate, :kill]
  defp capabilities_for("scout"), do: [:read]
  defp capabilities_for(_), do: [:read, :write]

  defp add_permission_args(args, cap) when cap in ["builder", "lead", "coordinator"],
    do: args ++ ["--dangerously-skip-permissions"]

  defp add_permission_args(args, "scout"),
    do:
      args ++
        [
          "--allowedTools",
          "Read",
          "Glob",
          "Grep",
          "WebSearch",
          "WebFetch",
          "Bash"
        ]

  defp add_permission_args(args, _), do: args

  defp tmux_args do
    if File.exists?(@ichor_socket), do: ["-S", @ichor_socket], else: ["-L", "obs"]
  end

  defp project_root, do: File.cwd!()

  # ── Private: Team Roster ──────────────────────────────────────────

  defp team_roster(session) do
    names = ~w(coordinator lead planner researcher-1 researcher-2)

    ids =
      Enum.map(names, fn name -> "  - #{name}: #{session}-#{name}" end)
      |> Enum.join("\n")

    """
    TEAM ROSTER (use these EXACT IDs with send_message/check_inbox):
    #{ids}
      - operator: operator (for final deliverables to the dashboard)

    Your session ID is: #{session}-YOUR_NAME (see below)
    """
  end

  # ── Private: Prompts ────────────────────────────────────────────────

  defp coordinator_prompt(run_id, roster) do
    """
    You are the MES Coordinator for manufacturing run #{run_id}.
    Your session_id is: mes-#{run_id}-coordinator

    #{roster}

    YOUR FIRST ACTION RIGHT NOW: call send_message to mes-#{run_id}-lead with content "Start research. Researchers send ideas to planner. Planner sends brief to me."

    YOUR SECOND ACTION: call check_inbox with session_id "mes-#{run_id}-coordinator". This is a pull-based inbox -- nothing arrives unless you call check_inbox. If empty, wait 30 seconds, call check_inbox again. Repeat this loop.

    WHEN YOU RECEIVE THE BRIEF: send the COMPLETE brief (all fields: TITLE, DESCRIPTION, SUBSYSTEM, SIGNAL_INTERFACE, TOPIC, VERSION, FEATURES, USE_CASES, ARCHITECTURE, DEPENDENCIES, SIGNALS_EMITTED, SIGNALS_SUBSCRIBED) to "operator" using send_message (from_session_id: "mes-#{run_id}-coordinator", to_session_id: "operator"). The operator (Archon) will create the project record. Also write it to subsystems/briefs/#{run_id}.md as a backup (mkdir -p subsystems/briefs first).

    DEADLINE: 10 minutes total. If no brief after 8 minutes, send whatever partial info you have to "operator" and write a fallback brief to disk.
    """
  end

  defp lead_prompt(run_id, roster) do
    """
    You are the MES Lead for manufacturing run #{run_id}.
    Your session_id is: mes-#{run_id}-lead

    #{roster}

    YOUR FIRST TWO ACTIONS RIGHT NOW:
    1. send_message to mes-#{run_id}-researcher-1 asking them to research ONE of: signal correlation, self-healing, entropy management, adaptive load balancing, or temporal reasoning
    2. send_message to mes-#{run_id}-researcher-2 asking them to research a DIFFERENT direction from the list above

    YOUR THIRD ACTION: call check_inbox with session_id "mes-#{run_id}-lead". This is a pull-based inbox -- nothing arrives unless you call check_inbox. If empty, wait 30 seconds, call check_inbox again. Repeat this loop.

    WHEN YOU RECEIVE RESEARCHER IDEAS: forward them to mes-#{run_id}-planner with send_message. Then keep polling check_inbox for the planner's brief and forward it to mes-#{run_id}-coordinator.

    CONSTRAINTS:
    - Subsystem must be controllable through Ichor.Signals. No external SaaS.
    - Creative, innovative, serious engineering for a sovereign AI control plane.
    - Do NOT go idle. KEEP POLLING check_inbox.
    """
  end

  defp planner_prompt(run_id, roster) do
    """
    You are the MES Planner for manufacturing run #{run_id}.
    Your session_id is: mes-#{run_id}-planner

    #{roster}

    YOUR FIRST ACTION RIGHT NOW: call the check_inbox MCP tool with session_id "mes-#{run_id}-planner". If the inbox is empty, wait 20 seconds, then call check_inbox again. Keep repeating this loop until you receive messages. This is a pull-based inbox -- nothing arrives unless you call check_inbox.

    WHEN YOU RECEIVE RESEARCHER IDEAS: synthesize them into a project brief and send_message to mes-#{run_id}-coordinator with this EXACT format (all fields required):

    TITLE: one short descriptive name
    DESCRIPTION: one or two sentences
    SUBSYSTEM: Elixir module name (e.g. Ichor.Subsystems.EntropyHarvester)
    SIGNAL_INTERFACE: which signals control it (e.g. "Subscribes to :all, emits :correlator_pattern_found")
    TOPIC: unique PubSub topic (e.g. subsystem:entropy_harvester) -- this is the subsystem's address
    VERSION: 0.1.0
    FEATURES: comma-separated list of capability descriptions
    USE_CASES: comma-separated list of concrete scenarios
    ARCHITECTURE: brief description of internal structure (processes, ETS tables, supervision)
    DEPENDENCIES: comma-separated Ichor modules required (e.g. Ichor.Signals, :ets)
    SIGNALS_EMITTED: comma-separated signal atoms this subsystem emits
    SIGNALS_SUBSCRIBED: comma-separated signal atoms or categories it listens to (or :all)

    RULES:
    - Do NOT read the codebase. Do NOT explore files. ONLY poll check_inbox and synthesize.
    - Subsystem must implement Ichor.Mes.Subsystem behaviour (info/0, start/0, handle_signal/1, stop/0)
    - info/0 returns an Ichor.Mes.Subsystem.Info struct with ALL the fields above
    - No external SaaS libraries. Must be controllable through Signals.
    - Max 3 turns after receiving ideas.
    """
  end

  defp researcher_prompt(run_id, n, roster) do
    """
    You are MES Researcher #{n} for manufacturing run #{run_id}.
    Your session_id is: mes-#{run_id}-researcher-#{n}

    #{roster}

    YOUR FIRST ACTION RIGHT NOW: call check_inbox with session_id "mes-#{run_id}-researcher-#{n}" to get your assignment. This is a pull-based inbox -- nothing arrives unless you call check_inbox. If empty, wait 15 seconds, call again.

    AFTER RECEIVING ASSIGNMENT: do max 3 web searches on your assigned topic, then send_message your proposal to mes-#{run_id}-planner with: subsystem name, single purpose, signal interface, key algorithm. Then stop.

    CONSTRAINTS:
    - Subsystem must be controllable through Ichor.Signals
    - No external SaaS dependencies. Single purpose. Creative and innovative.
    - MAX 3 turns total. Do NOT read the codebase or explore files.
    """
  end
end
