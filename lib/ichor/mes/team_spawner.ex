defmodule Ichor.Mes.TeamSpawner do
  @moduledoc """
  Compatibility facade over MES team lifecycle orchestration.
  """

  alias Ichor.Mes.TeamLifecycle

  @spec spawn_run(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate spawn_run(run_id, team_name), to: TeamLifecycle

  @spec kill_session(String.t()) :: :ok
  defdelegate kill_session(session), to: TeamLifecycle

  @spec spawn_corrective_agent(String.t(), String.t(), String.t() | nil, pos_integer()) ::
          :ok | {:error, term()}
  defdelegate spawn_corrective_agent(run_id, session, reason, attempt), to: TeamLifecycle

  @spec cleanup_old_runs() :: :ok
  defdelegate cleanup_old_runs(), to: TeamLifecycle

  @spec cleanup_orphaned_teams() :: :ok
  defdelegate cleanup_orphaned_teams(), to: TeamLifecycle
end
