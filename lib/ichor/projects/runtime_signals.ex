defmodule Ichor.Projects.RuntimeSignals do
  @moduledoc """
  Centralized Signals emission for DAG runtime events.
  """

  alias Ichor.Signals

  @job_signal_map %{
    job_claimed: {:dag_job_claimed, [:run_id, :external_id, :owner, :wave]},
    job_completed: {:dag_job_completed, [:run_id, :external_id, :owner]},
    job_failed: {:dag_job_failed, [:run_id, :external_id, :notes]},
    job_reset: {:dag_job_reset, [:run_id, :external_id]}
  }

  @doc "Emits a :dag_run_created signal with run metadata."
  @spec emit_run_created(String.t(), atom(), String.t(), non_neg_integer()) :: :ok
  def emit_run_created(run_id, source, label, job_count) do
    Signals.emit(:dag_run_created, %{
      run_id: run_id,
      source: source,
      label: label,
      job_count: job_count
    })
  end

  @doc "Emits a :dag_run_ready signal once the team is spawned."
  @spec emit_run_ready(String.t(), String.t(), String.t(), non_neg_integer(), non_neg_integer()) ::
          :ok
  def emit_run_ready(run_id, session, node_id, agent_count, worker_count) do
    Signals.emit(:dag_run_ready, %{
      run_id: run_id,
      session: session,
      node_id: node_id,
      agent_count: agent_count,
      worker_count: worker_count
    })
  end

  @doc "Emits a :dag_health_report signal with health status and issue count."
  @spec emit_health_report(String.t(), boolean(), non_neg_integer()) :: :ok
  def emit_health_report(run_id, healthy, issue_count) do
    Signals.emit(:dag_health_report, %{run_id: run_id, healthy: healthy, issue_count: issue_count})
  end

  @doc "Emits a :dag_tmux_gone signal when the tmux session is no longer alive."
  @spec emit_tmux_gone(String.t(), String.t()) :: :ok
  def emit_tmux_gone(run_id, session) do
    Signals.emit(:dag_tmux_gone, %{run_id: run_id, session: session})
  end

  @doc "Emits a :dag_run_completed signal when the coordinator delivers to operator."
  @spec emit_run_completed(String.t(), String.t()) :: :ok
  def emit_run_completed(run_id, label) do
    Signals.emit(:dag_run_completed, %{run_id: run_id, label: label})
  end

  @doc "Emits the appropriate signal for a job state transition."
  @spec emit_job_transition(map(), atom()) :: :ok
  def emit_job_transition(result, transition) do
    case Map.fetch(@job_signal_map, transition) do
      {:ok, {signal, keys}} ->
        payload = Map.take(result, keys) |> Map.new(fn {k, v} -> {k, v} end)
        Signals.emit(signal, payload)
        :ok

      :error ->
        :ok
    end
  end
end
