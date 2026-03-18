defmodule Ichor.SwarmMonitor.TaskState do
  @moduledoc """
  Side-effectful task mutation helpers used by SwarmMonitor.
  """

  defdelegate heal_task(path, task_id), to: Ichor.Tasks.JsonlStore
  defdelegate reassign_task(path, task_id, new_owner), to: Ichor.Tasks.JsonlStore
  defdelegate claim_task(task_id, agent_name, path), to: Ichor.Tasks.JsonlStore
  defdelegate update_task_status(path, task_id, status, owner), to: Ichor.Tasks.JsonlStore
end
