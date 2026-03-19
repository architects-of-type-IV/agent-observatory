defmodule Ichor.Dag.Actions do
  @moduledoc """
  Task mutation and corrective actions for the DAG runtime.
  """

  alias Ichor.Dag.Analysis
  alias Ichor.Dag.Projects
  alias Ichor.Fleet.Lifecycle.Cleanup
  alias Ichor.Tasks.JsonlStore

  def heal_task(state, task_id) do
    case Projects.tasks_jsonl_path_for_task(state, task_id) do
      nil -> {:error, :no_active_project}
      path -> JsonlStore.heal_task(path, task_id)
    end
  end

  def reassign_task(state, task_id, new_owner) do
    case Projects.tasks_jsonl_path_for_task(state, task_id) do
      nil -> {:error, :no_active_project}
      path -> JsonlStore.reassign_task(path, task_id, new_owner)
    end
  end

  def claim_task(state, task_id, agent_name) do
    case Projects.tasks_jsonl_path_for_task(state, task_id) do
      nil -> {:error, :no_active_project}
      path -> JsonlStore.claim_task(task_id, agent_name, path)
    end
  end

  def reset_all_stale(state, threshold_min) do
    case Projects.tasks_jsonl_path(state) do
      nil ->
        {:error, :no_active_project}

      path ->
        now = DateTime.utc_now()

        reset_count =
          Analysis.find_stale_tasks(state.tasks, now)
          |> Enum.filter(fn task -> stale_with_threshold?(task, now, threshold_min) end)
          |> Enum.reduce(0, &count_reset(&1, &2, path))

        {:ok, reset_count}
    end
  end

  def trigger_gc(state, team_name) do
    case Projects.tasks_jsonl_path(state) do
      nil -> {:error, :no_active_project}
      path -> Cleanup.trigger_gc(team_name, path)
    end
  end

  defp count_reset(task, acc, path) do
    case JsonlStore.update_task_status(path, task.id, "pending", "") do
      :ok -> acc + 1
      _ -> acc
    end
  end

  defp stale_with_threshold?(task, now, threshold_min) do
    case parse_timestamp(task.updated) do
      nil -> true
      timestamp -> DateTime.diff(now, timestamp, :minute) > threshold_min
    end
  end

  defp parse_timestamp(""), do: nil

  defp parse_timestamp(str) when is_binary(str) do
    str = String.replace(str, "Z", "")

    case DateTime.from_iso8601(str <> "Z") do
      {:ok, datetime, _} ->
        datetime

      _ ->
        case NaiveDateTime.from_iso8601(str) do
          {:ok, naive_datetime} -> DateTime.from_naive!(naive_datetime, "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp parse_timestamp(_), do: nil
end
