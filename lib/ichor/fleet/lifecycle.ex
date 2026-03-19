defmodule Ichor.Fleet.Lifecycle do
  @moduledoc """
  Public boundary for agent and team runtime lifecycle operations.
  """

  alias Ichor.Fleet.Lifecycle.AgentLaunch
  alias Ichor.Fleet.Lifecycle.Cleanup
  alias Ichor.Fleet.Lifecycle.TeamLaunch
  alias Ichor.Fleet.Lifecycle.TeamSpec

  @doc "Spawn a new agent from a launch opts map."
  @spec spawn_agent(AgentLaunch.launch_opts()) :: {:ok, map()} | {:error, term()}
  defdelegate spawn_agent(opts), to: AgentLaunch, as: :spawn

  @doc "Stop an agent process and clean up its backend resources."
  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  defdelegate stop_agent(agent_id), to: Cleanup

  @doc "Launch a multi-agent team from a TeamSpec."
  @spec launch_team(TeamSpec.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate launch_team(spec), to: TeamLaunch, as: :launch

  @doc "Launch a single agent into an existing tmux session."
  @spec launch_team_member(TeamSpec.t(), String.t()) :: :ok | {:error, term()}
  defdelegate launch_team_member(spec, session), to: TeamLaunch, as: :launch_into_existing_session

  @doc "Kill a tmux session by name."
  @spec kill_session(String.t()) :: :ok | {:error, term()}
  defdelegate kill_session(session), to: Cleanup

  @doc "Disband orphaned team supervisors whose names start with `prefix`."
  @spec cleanup_orphaned_teams(MapSet.t(String.t()), String.t()) :: :ok
  defdelegate cleanup_orphaned_teams(active_teams, prefix), to: Cleanup

  @doc "Kill orphaned tmux sessions whose names start with `prefix`."
  @spec cleanup_orphaned_tmux_sessions(MapSet.t(String.t()), String.t()) :: :ok
  defdelegate cleanup_orphaned_tmux_sessions(active_sessions, prefix), to: Cleanup
end
