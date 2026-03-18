defmodule Ichor.Fleet.Lifecycle do
  @moduledoc """
  Public boundary for agent and team runtime lifecycle operations.
  """

  alias Ichor.Fleet.Lifecycle.AgentLaunch
  alias Ichor.Fleet.Lifecycle.Cleanup
  alias Ichor.Fleet.Lifecycle.TeamLaunch
  alias Ichor.Fleet.Lifecycle.TeamSpec

  @spec spawn_agent(AgentLaunch.launch_opts()) :: {:ok, map()} | {:error, term()}
  defdelegate spawn_agent(opts), to: AgentLaunch, as: :spawn

  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  defdelegate stop_agent(agent_id), to: Cleanup

  @spec launch_team(TeamSpec.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate launch_team(spec), to: TeamLaunch, as: :launch

  @spec launch_team_member(TeamSpec.t(), String.t()) :: :ok | {:error, term()}
  defdelegate launch_team_member(spec, session), to: TeamLaunch, as: :launch_into_existing_session

  @spec kill_session(String.t()) :: :ok | {:error, term()}
  defdelegate kill_session(session), to: Cleanup

  @spec cleanup_orphaned_teams(MapSet.t(String.t()), String.t()) :: :ok
  defdelegate cleanup_orphaned_teams(active_teams, prefix), to: Cleanup

  @spec cleanup_orphaned_tmux_sessions(MapSet.t(String.t()), String.t()) :: :ok
  defdelegate cleanup_orphaned_tmux_sessions(active_sessions, prefix), to: Cleanup
end
