defmodule Ichor.Projects.ModeRunner do
  @moduledoc """
  Tmux session management and BEAM registration for Genesis mode teams.
  Handles prompt file writing, session/window creation, and fleet registration.
  Delegates shared helpers to Ichor.Control.TmuxHelpers.
  """

  alias Ichor.Control.Lifecycle.Registration
  alias Ichor.Control.TeamSupervisor
  alias Ichor.Control.TmuxHelpers

  @prompt_dir Path.expand("~/.ichor/genesis")

  @doc "Writes prompt files and shell launcher scripts for each agent."
  @spec write_agent_scripts(String.t(), String.t(), [map()]) :: :ok
  def write_agent_scripts(run_id, mode, agents) do
    dir = prompt_dir(run_id, mode)
    File.mkdir_p!(dir)

    Enum.each(agents, fn agent ->
      prompt_path = Path.join(dir, "#{agent.name}.txt")
      script_path = Path.join(dir, "#{agent.name}.sh")

      cli_args =
        ["--model", "sonnet"]
        |> TmuxHelpers.add_permission_args(agent.capability)
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

  @doc "Creates a new tmux session and runs the first agent in its initial window."
  @spec create_session_with_agent(String.t(), String.t(), String.t(), String.t(), map()) ::
          :ok | {:error, term()}
  def create_session_with_agent(session, cwd, run_id, mode, agent) do
    command = Path.join(prompt_dir(run_id, mode), "#{agent.name}.sh")

    args =
      TmuxHelpers.tmux_args() ++
        ["new-session", "-d", "-s", session, "-c", cwd, "-n", agent.name, command]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> {:error, {:session_create_failed, output, code}}
    end
  end

  @doc "Creates additional tmux windows for all agents after the first."
  @spec create_remaining_windows(String.t(), String.t(), String.t(), String.t(), [map()]) ::
          :ok | {:error, term()}
  def create_remaining_windows(session, cwd, run_id, mode, agents) do
    Enum.reduce_while(agents, :ok, fn agent, :ok ->
      command = Path.join(prompt_dir(run_id, mode), "#{agent.name}.sh")

      args =
        TmuxHelpers.tmux_args() ++
          ["new-window", "-t", session, "-n", agent.name, "-c", cwd, command]

      case System.cmd("tmux", args, stderr_to_stdout: true) do
        {_, 0} -> {:cont, :ok}
        {output, code} -> {:halt, {:error, {:window_create_failed, agent.name, output, code}}}
      end
    end)
  end

  @doc "Registers an agent with the fleet under the given team and session."
  @spec register_agent(String.t(), map(), String.t(), String.t(), String.t()) :: term()
  def register_agent(session, agent, team_name, run_id, cwd) do
    agent_id = "#{session}-#{agent.name}"

    process_opts = [
      id: agent_id,
      role: TmuxHelpers.capability_to_role(agent.capability),
      team: team_name,
      liveness_poll: true,
      backend: %{type: :tmux, session: "#{session}:#{agent.name}"},
      capabilities: TmuxHelpers.capabilities_for(agent.capability),
      metadata: %{cwd: cwd, run_id: run_id, model: "sonnet", genesis_mode: true}
    ]

    Registration.ensure_team(team_name)
    TeamSupervisor.spawn_member(team_name, process_opts)
  end

  @doc "Kills the tmux session and removes prompt files for the given run."
  @spec kill_session(String.t(), String.t(), String.t()) :: :ok
  def kill_session(session, run_id, mode) do
    Ichor.Signals.emit(:genesis_team_killed, %{session: session})
    kill_args = TmuxHelpers.tmux_args() ++ ["kill-session", "-t", session]
    System.cmd("tmux", kill_args, stderr_to_stdout: true)
    cleanup_prompt_files(run_id, mode)
    :ok
  end

  defp cleanup_prompt_files(run_id, mode) do
    dir = prompt_dir(run_id, mode)

    case File.rm_rf(dir) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  defp prompt_dir(run_id, mode), do: Path.join([@prompt_dir, "#{mode}-#{run_id}"])
end
