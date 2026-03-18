defmodule Ichor.Archon.TeamWatchdog.Reactions do
  @moduledoc """
  Pure decision logic for team lifecycle events.
  Takes signal data + state, returns action tuples. No DB calls, no side effects.
  """

  @type action ::
          {:archive_run, String.t()}
          | {:reset_jobs, String.t()}
          | {:notify_operator, String.t()}
          | {:disband_team, String.t()}
          | :noop

  @type state :: %{completed_runs: MapSet.t()}

  @spec react(atom(), map(), state()) :: {[action()], state()}
  def react(:dag_run_completed, %{run_id: run_id}, state) do
    {[:noop], %{state | completed_runs: MapSet.put(state.completed_runs, run_id)}}
  end

  def react(:dag_tmux_gone, %{run_id: run_id, session: session}, state) do
    case MapSet.member?(state.completed_runs, run_id) do
      true ->
        {[:noop], state}

      false ->
        actions = [
          {:archive_run, run_id},
          {:reset_jobs, run_id},
          {:disband_team, session},
          {:notify_operator, "DAG run #{run_id} died unexpectedly. Run archived, jobs reset."}
        ]

        {actions, state}
    end
  end

  def react(:genesis_tmux_gone, %{session: session}, state) do
    actions = [
      {:disband_team, session},
      {:notify_operator, "Genesis session #{session} died. Fleet disbanded."}
    ]

    {actions, state}
  end

  def react(:team_disbanded, %{team_name: "dag-" <> _ = name}, state) do
    case Enum.any?(state.completed_runs, fn id -> String.contains?(name, id) end) do
      true -> {[:noop], state}
      false -> {[{:notify_operator, "DAG team #{name} disbanded without completion."}], state}
    end
  end

  def react(:agent_crashed, %{session_id: _session_id}, state) do
    {[:noop], state}
  end

  def react(_signal, _data, state), do: {[:noop], state}

  @spec react_sweep([{String.t(), String.t(), boolean()}], state()) :: {[action()], state()}
  def react_sweep(run_checks, state) do
    actions =
      run_checks
      |> Enum.reject(fn {_run_id, _session, alive?} -> alive? end)
      |> Enum.flat_map(fn {run_id, session, _} ->
        [
          {:archive_run, run_id},
          {:reset_jobs, run_id},
          {:disband_team, session},
          {:notify_operator, "Orphaned DAG run #{run_id} (session #{session}) cleaned by sweep."}
        ]
      end)

    {actions, state}
  end
end
