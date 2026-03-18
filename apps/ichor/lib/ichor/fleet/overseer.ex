defmodule Ichor.Fleet.Overseer do
  @moduledoc """
  Public runtime oversight boundary for active swarm work.

  This is the human-facing runtime concept above project/task health,
  corrective actions, and active swarm state. It currently delegates to
  `Ichor.SwarmMonitor` while the implementation is being narrowed.
  """

  defdelegate get_state, to: Ichor.SwarmMonitor
  defdelegate set_active_project(project_key), to: Ichor.SwarmMonitor
  defdelegate add_project(key, path), to: Ichor.SwarmMonitor
  defdelegate heal_task(task_id), to: Ichor.SwarmMonitor
  defdelegate reassign_task(task_id, new_owner), to: Ichor.SwarmMonitor
  defdelegate reset_all_stale(threshold_min \\ 10), to: Ichor.SwarmMonitor
  defdelegate trigger_gc(team_name), to: Ichor.SwarmMonitor
  defdelegate run_health_check, to: Ichor.SwarmMonitor
  defdelegate claim_task(task_id, agent_name), to: Ichor.SwarmMonitor
end
