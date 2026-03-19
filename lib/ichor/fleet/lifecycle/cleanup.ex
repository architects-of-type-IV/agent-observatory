defmodule Ichor.Fleet.Lifecycle.Cleanup do
  @moduledoc """
  Lifecycle cleanup operations for agents, teams, and tmux-backed sessions.
  """

  alias Ichor.EventBuffer
  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Fleet.Lifecycle.Registration
  alias Ichor.Fleet.Lifecycle.TmuxLauncher
  alias Ichor.Fleet.Lifecycle.TmuxScript
  alias Ichor.Fleet.TeamSupervisor

  @gc_script Path.expand("~/.claude/skills/dag/scripts/gc.sh")

  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  def stop_agent(agent_id) do
    tmux_target = Registration.resolve_tmux_target(agent_id)
    _ = Registration.terminate(agent_id)

    result =
      if is_binary(tmux_target) do
        TmuxLauncher.send_exit(tmux_target)
      else
        :ok
      end

    EventBuffer.remove_session(agent_id)
    result
  end

  @spec kill_session(String.t()) :: :ok | {:error, term()}
  def kill_session(session), do: TmuxLauncher.kill_session(session)

  @doc "Remove the prompt directory created for an agent's launch scripts."
  @spec cleanup_prompt_dir(String.t()) :: :ok
  def cleanup_prompt_dir(dir), do: TmuxScript.cleanup_dir(dir)

  @spec cleanup_orphaned_teams(MapSet.t(String.t()), String.t()) :: :ok
  def cleanup_orphaned_teams(active_teams, prefix) do
    TeamSupervisor.list_all()
    |> Enum.filter(fn {name, _meta} -> String.starts_with?(name, prefix) end)
    |> Enum.reject(fn {name, _meta} -> MapSet.member?(active_teams, name) end)
    |> Enum.each(fn {name, _meta} -> FleetSupervisor.disband_team(name) end)

    :ok
  end

  @spec cleanup_orphaned_tmux_sessions(MapSet.t(String.t()), String.t()) :: :ok
  def cleanup_orphaned_tmux_sessions(active_sessions, prefix) do
    TmuxLauncher.list_sessions()
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.reject(&MapSet.member?(active_sessions, &1))
    |> Enum.each(&kill_session/1)

    :ok
  end

  @doc "Run the GC script for a team at `path`. Returns stdout on success or an error string."
  @spec trigger_gc(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def trigger_gc(team_name, path) do
    case System.cmd("bash", [@gc_script, team_name, path], stderr_to_stdout: true, env: []) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, String.trim(output)}
    end
  end
end
