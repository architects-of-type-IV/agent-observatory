defmodule Ichor.SwarmMonitor do
  @moduledoc """
  Compatibility facade over `Ichor.Dag.Runtime`.

  Legacy callers may still reference `Ichor.SwarmMonitor`, but the active
  runtime process and primary API now live under `Ichor.Dag`.
  """
  defdelegate start_link(opts), to: Ichor.Dag.Runtime
  defdelegate get_state, to: Ichor.Dag.Runtime, as: :state
  defdelegate set_active_project(project_key), to: Ichor.Dag.Runtime
  defdelegate add_project(key, path), to: Ichor.Dag.Runtime
  defdelegate heal_task(task_id), to: Ichor.Dag.Runtime
  defdelegate reassign_task(task_id, new_owner), to: Ichor.Dag.Runtime
  defdelegate reset_all_stale(threshold_min \\ 10), to: Ichor.Dag.Runtime
  defdelegate trigger_gc(team_name), to: Ichor.Dag.Runtime
  defdelegate run_health_check, to: Ichor.Dag.Runtime
  defdelegate claim_task(task_id, agent_name), to: Ichor.Dag.Runtime
end
