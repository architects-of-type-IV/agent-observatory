defmodule Ichor.Archon.TeamWatchdog.Reactions do
  @moduledoc """
  Pure decision logic for team lifecycle signals.
  Takes signal name + data + state, returns action tuples.
  No DB calls, no side effects, no timers.
  """

  @type action ::
          {:archive_run, String.t()}
          | {:reset_jobs, String.t()}
          | {:notify_operator, String.t()}
          | {:disband_team, String.t()}
          | :noop

  @type state :: %{completed_runs: MapSet.t()}

  @spec react(atom(), map(), state()) :: {[action()], state()}

  # Clean completion -- record it so we don't false-positive on disband
  def react(:dag_run_completed, %{run_id: run_id}, state) do
    {[:noop], %{state | completed_runs: MapSet.put(state.completed_runs, run_id)}}
  end

  # DAG tmux session died -- RunProcess detected it and emitted this signal
  def react(:dag_tmux_gone, %{run_id: run_id, session: session}, state) do
    case MapSet.member?(state.completed_runs, run_id) do
      true -> {[:noop], state}
      false -> {dag_cleanup_actions(run_id, session, "tmux session died"), state}
    end
  end

  # Fleet team disbanded -- check if it was a DAG team that didn't complete
  def react(:team_disbanded, %{team_name: "dag-" <> _ = session}, state) do
    case Enum.any?(state.completed_runs, &String.contains?(session, &1)) do
      true -> {[:noop], state}
      false -> {[{:notify_operator, "DAG team #{session} disbanded without completion."}], state}
    end
  end

  # Genesis tmux session died
  def react(:genesis_tmux_gone, %{session: session}, state) do
    {[
       {:disband_team, session},
       {:notify_operator, "Genesis session #{session} died. Fleet disbanded."}
     ], state}
  end

  # Agent stopped -- if it's a coordinator/lead, the team is headless
  def react(:agent_stopped, %{session_id: id, role: role}, state)
      when role in [:coordinator, :lead] do
    case extract_dag_session(id) do
      nil ->
        {[:noop], state}

      session ->
        {[{:notify_operator, "DAG #{role} #{id} stopped. Team #{session} may be headless."}],
         state}
    end
  end

  def react(_signal, _data, state), do: {[:noop], state}

  defp dag_cleanup_actions(run_id, session, reason) do
    [
      {:archive_run, run_id},
      {:reset_jobs, run_id},
      {:disband_team, session},
      {:notify_operator, "DAG run #{run_id} cleaned up: #{reason}. Jobs reset."}
    ]
  end

  defp extract_dag_session("dag-" <> _ = id) do
    case String.split(id, "-", parts: 3) do
      ["dag", hex, _role] -> "dag-#{hex}"
      _ -> nil
    end
  end

  defp extract_dag_session(_), do: nil
end
