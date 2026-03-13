defmodule Ichor.Mes.TeamSpawner do
  @moduledoc """
  Spawns a 5-agent MES team inside a single tmux session.

  Flow:
    1. Write per-agent prompt files to ~/.ichor/mes/{run_id}/
    2. Create one tmux session: `mes-{run_id}`
    3. Launch Claude in each window with its prompt file piped via stdin
    4. Register each agent in BEAM fleet (AgentProcess with liveness_poll under Fleet.TeamSupervisor)
    5. Return session name so Scheduler can set a kill timer

  All agents start in the observatory project root so they have access to
  the MCP server config (.mcp.json). Communication between agents flows
  through the Ichor app via send_message/check_inbox MCP tools.
  """

  alias Ichor.Fleet.{FleetSupervisor, TeamSupervisor}
  alias Ichor.Mes.RunProcess
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

  @spec spawn_corrective_agent(String.t(), String.t(), String.t() | nil, pos_integer()) ::
          :ok | {:error, term()}
  def spawn_corrective_agent(run_id, session, reason, attempt) do
    cwd = project_root()
    name = "corrective-#{attempt}"

    agent = %{
      name: name,
      capability: "builder",
      prompt: corrective_prompt(run_id, session, reason)
    }

    dir = prompt_dir(run_id)
    File.mkdir_p!(dir)

    prompt_path = Path.join(dir, "#{name}.txt")
    script_path = Path.join(dir, "#{name}.sh")

    cli_args =
      ["--model", "sonnet"]
      |> add_permission_args(agent.capability)
      |> Enum.join(" ")

    File.write!(prompt_path, agent.prompt)

    File.write!(
      script_path,
      "#!/bin/sh\ncat #{prompt_path} | env -u CLAUDECODE claude #{cli_args}\n"
    )

    File.chmod!(script_path, 0o755)

    args =
      tmux_args() ++
        ["new-window", "-t", session, "-n", name, "-c", cwd, build_agent_command(agent, run_id)]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_, 0} ->
        register_agent(session, agent, "mes-#{run_id}", run_id, cwd)
        :ok

      {output, code} ->
        Signals.emit(:mes_tmux_spawn_failed, %{session: session, output: output, exit_code: code})
        {:error, {:corrective_spawn_failed, output, code}}
    end
  end

  @spec cleanup_old_runs() :: :ok
  def cleanup_old_runs do
    cleanup_prompt_dir()
    cleanup_orphaned_teams()
    :ok
  end

  defp cleanup_prompt_dir do
    case File.ls(@prompt_dir) do
      {:ok, dirs} -> Enum.each(dirs, &remove_if_directory/1)
      {:error, _} -> :ok
    end
  end

  defp remove_if_directory(dir) do
    path = Path.join(@prompt_dir, dir)

    if File.dir?(path) do
      File.rm_rf!(path)
      Signals.emit(:mes_cleanup, %{target: dir})
    end
  end

  @spec cleanup_orphaned_teams() :: :ok
  def cleanup_orphaned_teams do
    active_teams =
      RunProcess.list_all()
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
      liveness_poll: true,
      backend: %{type: :tmux, session: "#{session}:#{agent.name}"},
      capabilities: capabilities_for(agent.capability),
      metadata: %{cwd: cwd, run_id: run_id, model: "sonnet"}
    ]

    ensure_team(team_name)

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
    case FleetSupervisor.create_team(name: name) do
      {:ok, _pid} -> :ok
      {:error, :already_exists} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp capabilities_for("lead"), do: [:read, :write, :spawn, :assign, :escalate]
  defp capabilities_for("coordinator"), do: [:read, :write, :spawn, :assign, :escalate, :kill]
  defp capabilities_for("scout"), do: [:read]
  defp capabilities_for(_), do: [:read, :write]

  # ── Private: Role/Permission Helpers ───────────────────────────────

  defp capability_to_role("lead"), do: :lead
  defp capability_to_role("coordinator"), do: :coordinator
  defp capability_to_role(_), do: :worker

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

    ids = Enum.map_join(names, "\n", fn name -> "  - #{name}: #{session}-#{name}" end)

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
    You are in charge. You drive the entire pipeline.

    #{roster}

    CRITICAL RULES -- READ BEFORE DOING ANYTHING:
    - You communicate ONLY by calling the send_message and check_inbox MCP tools.
    - NEVER write text to describe what you would send. ALWAYS call the tool.
    - If you find yourself typing "I would send..." STOP. Call send_message instead.
    - Every message MUST go through send_message. No exceptions.

    ============================================================
    PHASE 1: DISPATCH (do ALL of these RIGHT NOW, one after another)
    ============================================================

    Call send_message 4 times in sequence:

    1. from: "mes-#{run_id}-coordinator", to: "mes-#{run_id}-researcher-1"
       content: "You are assigned: signal correlation OR entropy management OR temporal reasoning (pick one). Do up to 3 web searches, then call send_message to mes-#{run_id}-coordinator with your proposal. Include: subsystem name, purpose, signal interface, key algorithm. You MUST call send_message when done."

    2. from: "mes-#{run_id}-coordinator", to: "mes-#{run_id}-researcher-2"
       content: "You are assigned: self-healing OR adaptive load balancing OR anomaly detection (pick one, different from researcher-1). Do up to 3 web searches, then call send_message to mes-#{run_id}-coordinator with your proposal. Include: subsystem name, purpose, signal interface, key algorithm. You MUST call send_message when done."

    3. from: "mes-#{run_id}-coordinator", to: "mes-#{run_id}-planner"
       content: "Stand by. I will forward researcher proposals to you shortly. When you receive them, synthesize into a brief and send_message it back to mes-#{run_id}-coordinator."

    4. from: "mes-#{run_id}-coordinator", to: "mes-#{run_id}-lead"
       content: "Stand by as quality reviewer. I will send you the final brief for review before delivery."

    ============================================================
    PHASE 2: COLLECT (poll inbox, forward to planner)
    ============================================================

    After dispatching, call check_inbox with session_id "mes-#{run_id}-coordinator".
    If empty, wait 20 seconds, call check_inbox again. REPEAT.

    When you receive a researcher proposal:
    - Forward it to the planner: send_message from "mes-#{run_id}-coordinator" to "mes-#{run_id}-planner"
    - Keep polling for the second researcher
    - After forwarding both (or after 5 minutes if only one arrived), send_message to planner: "Synthesize now with what you have. Send the brief back to me."

    ============================================================
    PHASE 3: DELIVER (send brief to operator)
    ============================================================

    When you receive the synthesized brief from the planner:
    - Send it to lead for quick review: send_message to "mes-#{run_id}-lead"
    - Then send it to operator: send_message from "mes-#{run_id}-coordinator" to "operator"

    The content to operator MUST be plain text starting with "TITLE:" on the first line:
    TITLE: short descriptive name
    DESCRIPTION: one or two sentences
    SUBSYSTEM: Elixir module name (e.g. Ichor.Subsystems.EntropyHarvester)
    SIGNAL_INTERFACE: which signals control it
    TOPIC: unique PubSub topic (e.g. subsystem:entropy_harvester)
    VERSION: 0.1.0
    FEATURES: comma-separated list
    USE_CASES: comma-separated list
    ARCHITECTURE: brief description of internal structure
    DEPENDENCIES: comma-separated Ichor modules required
    SIGNALS_EMITTED: comma-separated signal atoms
    SIGNALS_SUBSCRIBED: comma-separated signal atoms or categories

    No markdown. No headers. No extra text before TITLE.

    Also write the brief to subsystems/briefs/#{run_id}.md (mkdir -p subsystems/briefs first).

    ============================================================
    DEADLINE & FALLBACK
    ============================================================
    If after 7 minutes you have ANY researcher proposals but no planner brief:
    - Synthesize the brief yourself from the proposals you have
    - Send it to operator via send_message
    - Write it to disk
    If after 8 minutes you have NOTHING: write a note to subsystems/briefs/#{run_id}.md explaining the failure.
    """
  end

  defp lead_prompt(run_id, roster) do
    """
    You are the MES Lead (quality reviewer) for manufacturing run #{run_id}.
    Your session_id is: mes-#{run_id}-lead

    #{roster}

    CRITICAL RULES:
    - You communicate ONLY by calling send_message and check_inbox MCP tools.
    - NEVER write text to describe what you would send. ALWAYS call the tool.

    YOUR JOB: You are a quality reviewer. The coordinator runs the pipeline.

    STEP 1: Call check_inbox with session_id "mes-#{run_id}-lead" RIGHT NOW.
    If empty, wait 20 seconds, call check_inbox again. REPEAT.

    STEP 2: When you receive the brief from the coordinator for review:
    - Check it has all required fields (TITLE, DESCRIPTION, SUBSYSTEM, SIGNAL_INTERFACE, TOPIC, VERSION, FEATURES, USE_CASES, ARCHITECTURE, DEPENDENCIES, SIGNALS_EMITTED, SIGNALS_SUBSCRIBED)
    - Check it proposes something creative and technically sound
    - Call send_message back to mes-#{run_id}-coordinator with either "APPROVED" or specific feedback

    STEP 3: If any agent messages you asking for help, forward the message to the coordinator via send_message.

    Do NOT go idle. KEEP POLLING check_inbox.
    """
  end

  defp planner_prompt(run_id, roster) do
    """
    You are the MES Planner for manufacturing run #{run_id}.
    Your session_id is: mes-#{run_id}-planner

    #{roster}

    CRITICAL RULES:
    - You communicate ONLY by calling send_message and check_inbox MCP tools.
    - NEVER write text to describe what you would send. ALWAYS call the tool.
    - Do NOT read the codebase. Do NOT explore files. ONLY poll check_inbox and synthesize.

    STEP 1: Call check_inbox with session_id "mes-#{run_id}-planner" RIGHT NOW.
    If empty, wait 20 seconds, call check_inbox again. REPEAT until you receive researcher ideas from the coordinator.

    STEP 2: When you receive researcher proposals, synthesize them into a project brief.
    Then IMMEDIATELY call send_message with:
      from_session_id: "mes-#{run_id}-planner"
      to_session_id: "mes-#{run_id}-coordinator"
      content: the brief in this EXACT format (all fields required, one per line):

    TITLE: one short descriptive name
    DESCRIPTION: one or two sentences
    SUBSYSTEM: Elixir module name (e.g. Ichor.Subsystems.EntropyHarvester)
    SIGNAL_INTERFACE: which signals control it
    TOPIC: unique PubSub topic (e.g. subsystem:entropy_harvester)
    VERSION: 0.1.0
    FEATURES: comma-separated list
    USE_CASES: comma-separated list
    ARCHITECTURE: brief description of internal structure
    DEPENDENCIES: comma-separated Ichor modules required
    SIGNALS_EMITTED: comma-separated signal atoms
    SIGNALS_SUBSCRIBED: comma-separated signal atoms or categories

    You MUST call send_message to deliver this. Do NOT just write the brief as text output.

    RULES:
    - Subsystem must implement Ichor.Mes.Subsystem behaviour (info/0, start/0, handle_signal/1, stop/0)
    - No external SaaS libraries. Must be controllable through Signals.
    - Max 3 turns after receiving ideas. Send the brief via send_message, then stop.
    """
  end

  defp researcher_prompt(run_id, n, roster) do
    """
    You are MES Researcher #{n} for manufacturing run #{run_id}.
    Your session_id is: mes-#{run_id}-researcher-#{n}

    #{roster}

    CRITICAL RULES:
    - You communicate ONLY by calling send_message and check_inbox MCP tools.
    - NEVER write text to describe what you would send. ALWAYS call the tool.
    - Do NOT read the codebase. Do NOT explore files.

    STEP 1: Call check_inbox with session_id "mes-#{run_id}-researcher-#{n}" RIGHT NOW.
    If empty, wait 15 seconds, call check_inbox again. REPEAT until you receive your assignment.

    STEP 2: Do up to 3 web searches on your assigned topic.

    STEP 3 (THIS IS THE MOST IMPORTANT STEP -- THE WHOLE TEAM DEPENDS ON THIS):
    Call send_message with:
      from_session_id: "mes-#{run_id}-researcher-#{n}"
      to_session_id: "mes-#{run_id}-coordinator"
      content: your proposal including subsystem name, single purpose, signal interface, key algorithm

    YOU MUST CALL send_message. If you do not, your research is LOST and the entire team stalls forever. The coordinator is waiting for your message. There is no other way to deliver your work.

    After calling send_message, you are done. Stop.

    CONSTRAINTS:
    - Subsystem must be controllable through Ichor.Signals
    - No external SaaS dependencies. Single purpose. Creative and innovative.
    - MAX 5 tool calls total: 1 check_inbox + 3 web searches + 1 send_message.
    """
  end

  defp corrective_prompt(run_id, session, reason) do
    roster = team_roster(session)

    """
    You are a Corrective Agent for MES manufacturing run #{run_id}.
    Your session_id is: #{session}-corrective

    #{roster}

    CONTEXT: The quality gate rejected the brief submitted by this run's coordinator.
    FAILURE REASON: #{reason || "unspecified — check your inbox for details"}

    YOUR TASK (MAX 5 tool calls total):
    1. Call check_inbox with session_id "#{session}-corrective" for additional context.
    2. Synthesize a corrected subsystem brief that addresses the failure reason.
    3. Call send_message to operator with the corrected brief in this EXACT format:

    TITLE: short descriptive name
    DESCRIPTION: one or two sentences
    SUBSYSTEM: Elixir module name (e.g. Ichor.Subsystems.Foo)
    SIGNAL_INTERFACE: which signals control it
    TOPIC: unique PubSub topic
    VERSION: 0.1.0
    FEATURES: comma-separated list
    USE_CASES: comma-separated list
    ARCHITECTURE: brief description of internal structure
    DEPENDENCIES: comma-separated Ichor modules required
    SIGNALS_EMITTED: comma-separated signal atoms
    SIGNALS_SUBSCRIBED: comma-separated signal atoms or categories

    No markdown. No headers. No extra text before TITLE.
    Also write the brief to subsystems/briefs/#{run_id}.md (overwrite).

    After calling send_message, you are done. Stop.
    """
  end
end
