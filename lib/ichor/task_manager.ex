defmodule Ichor.TaskManager do
  @moduledoc """
  Task CRUD operations for file-based task storage.
  Tasks are stored as JSON files in ~/.claude/tasks/{team_name}/{id}.json
  """
  defdelegate create_task(team_name, attrs), to: Ichor.Tasks.TeamStore
  defdelegate update_task(team_name, task_id, changes), to: Ichor.Tasks.TeamStore
  defdelegate get_task(team_name, task_id), to: Ichor.Tasks.TeamStore
  defdelegate list_tasks(team_name), to: Ichor.Tasks.TeamStore
  defdelegate delete_task(team_name, task_id), to: Ichor.Tasks.TeamStore
  defdelegate next_task_id(team_name), to: Ichor.Tasks.TeamStore
end
