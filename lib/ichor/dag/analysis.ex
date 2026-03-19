defmodule Ichor.Dag.Analysis do
  @moduledoc """
  Task parsing and derived DAG runtime projection.
  """

  alias Ichor.Dag.Graph

  @doc "Reloads tasks from all watched projects and updates derived DAG state."
  @spec refresh_tasks(map()) :: map()
  def refresh_tasks(state) do
    all_tasks =
      state.watched_projects
      |> Enum.flat_map(fn {key, path} ->
        path
        |> Path.join("tasks.jsonl")
        |> parse_tasks_jsonl()
        |> Enum.map(fn task -> %{task | project: key} end)
      end)

    case all_tasks do
      [] ->
        %{
          state
          | tasks: [],
            pipeline: empty_pipeline(),
            dag: empty_dag(),
            stale_tasks: [],
            file_conflicts: []
        }

      tasks ->
        nodes = Enum.map(tasks, &Graph.to_graph_node/1)

        %{
          state
          | tasks: tasks,
            pipeline: Graph.pipeline_stats(nodes),
            dag: Graph.dag(nodes),
            stale_tasks: stale_tasks(tasks, DateTime.utc_now()),
            file_conflicts: file_conflicts(tasks)
        }
    end
  end

  @doc "Parses a tasks.jsonl file into normalized task maps, skipping deleted entries."
  @spec parse_tasks_jsonl(String.t()) :: [map()]
  def parse_tasks_jsonl(path) do
    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.map(&decode_task_line/1)
      |> Enum.reject(fn task -> is_nil(task) or task.status == "deleted" end)
    else
      []
    end
  end

  @doc "Returns tasks that have been in_progress beyond the stale threshold."
  @spec find_stale_tasks([map()], DateTime.t()) :: [map()]
  def find_stale_tasks(tasks, now), do: stale_tasks(tasks, now)

  defp empty_pipeline,
    do: %{total: 0, pending: 0, in_progress: 0, completed: 0, failed: 0, blocked: 0}

  defp empty_dag, do: %{waves: [], edges: [], critical_path: []}

  defp decode_task_line(line) do
    case Jason.decode(String.trim(line)) do
      {:ok, task} -> normalize_task(task)
      _ -> nil
    end
  end

  defp normalize_task(task) do
    %{
      id: field(task, "id", ""),
      status: field(task, "status", "pending"),
      subject: field(task, "subject", ""),
      description: field(task, "description", ""),
      owner: field(task, "owner", ""),
      priority: field(task, "priority", "medium"),
      blocked_by: field(task, "blocked_by", []),
      files: field(task, "files", []),
      done_when: field(task, "done_when", ""),
      updated: task["updated"] || task["created"] || "",
      notes: field(task, "notes", ""),
      tags: field(task, "tags", []),
      project: ""
    }
  end

  defp field(map, key, default), do: map[key] || default

  defp stale_tasks(tasks, now) do
    tasks
    |> Enum.map(&Graph.to_graph_node/1)
    |> Graph.stale_items(now, 10)
    |> Enum.map(fn node -> Enum.find(tasks, &(&1.id == node.id)) end)
  end

  defp file_conflicts(tasks) do
    tasks
    |> Enum.map(&Graph.to_graph_node/1)
    |> Graph.file_conflicts()
  end
end
