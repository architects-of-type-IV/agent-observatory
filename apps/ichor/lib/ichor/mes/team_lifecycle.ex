defmodule Ichor.Mes.TeamLifecycle do
  @moduledoc """
  MES-specific launch and cleanup coordination over generic lifecycle modules.
  """

  alias Ichor.Mes.TeamCleanup
  alias Ichor.Mes.TeamSpecBuilder
  alias Ichor.Signals

  @spec spawn_run(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def spawn_run(run_id, team_name) do
    builder = team_spec_builder()
    launch = launch_module()
    spec = builder.build_team_spec(run_id, team_name)
    session = spec.session

    with {:ok, ^session} <- launch.launch(spec) do
      Signals.emit(:mes_team_ready, %{session: session, agent_count: length(spec.agents)})
      {:ok, session}
    else
      {:error, reason} = error ->
        Signals.emit(:mes_team_spawn_failed, %{session: session, reason: inspect(reason)})
        error
    end
  end

  @spec spawn_corrective_agent(String.t(), String.t(), String.t() | nil, pos_integer()) ::
          :ok | {:error, term()}
  def spawn_corrective_agent(run_id, session, reason, attempt) do
    builder = team_spec_builder()
    launch = launch_module()
    spec = builder.build_corrective_team_spec(run_id, session, reason, attempt)

    case launch.launch_into_existing_session(spec, session) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec kill_session(String.t()) :: :ok
  def kill_session(session), do: cleanup_module().kill_session(session)

  @spec cleanup_old_runs() :: :ok
  def cleanup_old_runs, do: cleanup_module().cleanup_old_runs()

  @spec cleanup_orphaned_teams() :: :ok
  def cleanup_orphaned_teams, do: cleanup_module().cleanup_orphaned_teams()

  defp team_spec_builder do
    Application.get_env(:ichor, :mes_team_spec_builder_module, TeamSpecBuilder)
  end

  defp launch_module do
    Application.get_env(:ichor, :mes_team_launch_module, Ichor.Fleet.Lifecycle.TeamLaunch)
  end

  defp cleanup_module do
    Application.get_env(:ichor, :mes_team_cleanup_module, TeamCleanup)
  end
end
