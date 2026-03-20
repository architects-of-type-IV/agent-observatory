defmodule Ichor.Projects.Runner.Hooks.MES do
  @moduledoc """
  MES-specific runner hook implementations.

  Handles quality gate reactions and corrective agent spawning.
  These are the behaviors that differ from the generic Runner core.
  """

  alias Ichor.Control.Lifecycle.TeamLaunch
  alias Ichor.Projects.{Janitor, TeamCleanup, TeamSpecBuilder}
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @doc "Called from Mode timer on_init. Launches the MES tmux team and registers with the Janitor."
  @spec on_init(struct()) :: :ok
  def on_init(state) do
    pid = self()

    team_name =
      get_in(state.config, [Access.key(:hooks), Access.key(:team_name)]) || state.session

    spec = team_spec_builder().build_team_spec(state.run_id, team_name)

    case team_launch().launch(spec) do
      {:ok, _session} ->
        :ok

      {:error, reason} ->
        Signals.emit(:mes_cycle_failed, %{run_id: state.run_id, reason: inspect(reason)})
    end

    Janitor.monitor_run(state.run_id, pid)
    :ok
  end

  @doc "Dispatches incoming signals for MES-specific reactions."
  @spec on_signal(Message.t(), struct()) :: struct()
  def on_signal(
        %Message{name: :mes_quality_gate_failed, data: %{run_id: run_id} = data},
        %{run_id: run_id} = state
      ) do
    failures = Map.get(state.runtime, :gate_failures, 0) + 1

    spawn_corrective_agent(state.run_id, state.session, data[:reason], failures)

    put_in(state.runtime[:gate_failures], failures)
  end

  def on_signal(
        %Message{name: :mes_quality_gate_escalated, data: %{run_id: run_id}},
        %{run_id: run_id} = state
      ) do
    %{state | deadline_passed: true}
  end

  def on_signal(_msg, state), do: state

  @doc "Performs MES cleanup: kills the tmux session."
  @spec cleanup(struct()) :: :ok
  def cleanup(state) do
    team_cleanup().kill_session(state.session)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp spawn_corrective_agent(run_id, session, reason, attempt) do
    builder = team_spec_builder()
    spec = builder.build_corrective_team_spec(run_id, session, reason, attempt)

    case team_launch().launch_into_existing_session(spec, session) do
      :ok ->
        Signals.emit(:mes_corrective_agent_spawned, %{
          run_id: run_id,
          session: session,
          attempt: attempt
        })

      {:error, err} ->
        Signals.emit(:mes_corrective_agent_failed, %{
          run_id: run_id,
          session: session,
          reason: inspect(err)
        })
    end
  end

  defp team_spec_builder do
    Application.get_env(:ichor, :mes_team_spec_builder_module, TeamSpecBuilder)
  end

  defp team_launch do
    Application.get_env(:ichor, :mes_team_launch_module, TeamLaunch)
  end

  defp team_cleanup do
    Application.get_env(:ichor, :mes_team_cleanup_module, TeamCleanup)
  end
end
