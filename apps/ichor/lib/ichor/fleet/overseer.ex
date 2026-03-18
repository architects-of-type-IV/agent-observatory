defmodule Ichor.Fleet.Overseer do
  @moduledoc """
  Public runtime oversight boundary for active swarm work.

  This is the human-facing runtime concept above project/task health,
  corrective actions, and active pipeline state. It currently acts as a
  compatibility façade over the DAG runtime surface while the old
  SwarmMonitor naming is retired.
  """

  defdelegate get_state, to: Ichor.Dag.Status, as: :state
  defdelegate set_active_project(project_key), to: Ichor.Dag.Status
  defdelegate add_project(key, path), to: Ichor.Dag.Status
  defdelegate heal_task(task_id), to: Ichor.Dag.Claims
  defdelegate reassign_task(task_id, new_owner), to: Ichor.Dag.Claims
  defdelegate reset_all_stale(threshold_min \\ 10), to: Ichor.Dag.Claims, as: :reset_stale
  defdelegate trigger_gc(team_name), to: Ichor.Dag.GC, as: :trigger
  defdelegate run_health_check, to: Ichor.Dag.Health, as: :check
  defdelegate claim_task(task_id, agent_name), to: Ichor.Dag.Claims
end
