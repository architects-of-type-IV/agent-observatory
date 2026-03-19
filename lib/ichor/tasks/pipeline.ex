defmodule Ichor.Tasks.Pipeline do
  @moduledoc """
  Unified action layer for project `tasks.jsonl` pipelines.
  """

  alias Ichor.Tasks.JsonlStore

  def heal_task(path, task_id), do: JsonlStore.heal_task(path, task_id)

  def reassign_task(path, task_id, new_owner),
    do: JsonlStore.reassign_task(path, task_id, new_owner)

  def claim_task(task_id, agent_name, path), do: JsonlStore.claim_task(task_id, agent_name, path)

  def update_task_status(path, task_id, status, owner),
    do: JsonlStore.update_task_status(path, task_id, status, owner)
end
