defmodule Ichor.Genesis.ModeRunner do
  @moduledoc """
  Tmux session management and BEAM registration for Genesis mode teams.
  Handles prompt file writing, session/window creation, and fleet registration.
  """

  alias Ichor.Fleet.{FleetSupervisor, TeamSupervisor}

  @prompt_dir Path.expand("~/.ichor/genesis")
  @ichor_socket Path.expand("~/.ichor/tmux/obs.sock")

  @spec write_agent_scripts(String.t(), String.t(), [map()]) :: :ok
  def write_agent_scripts(run_id, mode, agents) do
    dir = prompt_dir(run_id, mode)
    File.mkdir_p!(dir)

    Enum.each(agents, fn agent ->
      prompt_path = Path.join(dir, "#{agent.name}.txt")
      script_path = Path.join(dir, "#{agent.name}.sh")

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
    end)

    :ok
  end

  @spec create_session_with_agent(String.t(), String.t(), String.t(), String.t(), map()) ::
          :ok | {:error, term()}
  def create_session_with_agent(session, cwd, run_id, mode, agent) do
    command = Path.join(prompt_dir(run_id, mode), "#{agent.name}.sh")

    args =
      tmux_args() ++ ["new-session", "-d", "-s", session, "-c", cwd, "-n", agent.name, command]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> {:error, {:session_create_failed, output, code}}
    end
  end

  @spec create_remaining_windows(String.t(), String.t(), String.t(), String.t(), [map()]) ::
          :ok | {:error, term()}
  def create_remaining_windows(session, cwd, run_id, mode, agents) do
    Enum.reduce_while(agents, :ok, fn agent, :ok ->
      command = Path.join(prompt_dir(run_id, mode), "#{agent.name}.sh")
      args = tmux_args() ++ ["new-window", "-t", session, "-n", agent.name, "-c", cwd, command]

      case System.cmd("tmux", args, stderr_to_stdout: true) do
        {_, 0} -> {:cont, :ok}
        {output, code} -> {:halt, {:error, {:window_create_failed, agent.name, output, code}}}
      end
    end)
  end

  @spec register_agent(String.t(), map(), String.t(), String.t(), String.t()) :: term()
  def register_agent(session, agent, team_name, run_id, cwd) do
    agent_id = "#{session}-#{agent.name}"

    process_opts = [
      id: agent_id,
      role: capability_to_role(agent.capability),
      team: team_name,
      liveness_poll: true,
      backend: %{type: :tmux, session: "#{session}:#{agent.name}"},
      capabilities: capabilities_for(agent.capability),
      metadata: %{cwd: cwd, run_id: run_id, model: "sonnet", genesis_mode: true}
    ]

    ensure_team(team_name)
    TeamSupervisor.spawn_member(team_name, process_opts)
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp ensure_team(name) do
    case FleetSupervisor.create_team(name: name) do
      {:ok, _pid} -> :ok
      {:error, :already_exists} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp prompt_dir(run_id, mode), do: Path.join([@prompt_dir, "#{mode}-#{run_id}"])

  defp tmux_args do
    case File.exists?(@ichor_socket) do
      true -> ["-S", @ichor_socket]
      false -> ["-L", "obs"]
    end
  end

  defp capability_to_role("coordinator"), do: :coordinator
  defp capability_to_role("lead"), do: :lead
  defp capability_to_role(_), do: :worker

  defp capabilities_for("coordinator"), do: [:read, :write, :spawn, :assign, :escalate, :kill]
  defp capabilities_for("lead"), do: [:read, :write, :spawn, :assign, :escalate]
  defp capabilities_for("scout"), do: [:read]
  defp capabilities_for(_), do: [:read, :write]

  defp add_permission_args(args, cap) when cap in ["builder", "lead", "coordinator"],
    do: args ++ ["--dangerously-skip-permissions"]

  defp add_permission_args(args, "scout"),
    do: args ++ ["--allowedTools", "Read", "Glob", "Grep", "WebSearch", "WebFetch", "Bash"]

  defp add_permission_args(args, _), do: args
end
