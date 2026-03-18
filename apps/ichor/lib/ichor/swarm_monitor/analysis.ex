defmodule Ichor.SwarmMonitor.Analysis do
  @moduledoc """
  Task parsing and derived swarm-state projection.
  """

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
        %{
          state
          | tasks: tasks,
            pipeline: compute_pipeline(tasks),
            dag: compute_dag(tasks),
            stale_tasks: find_stale_tasks(tasks, DateTime.utc_now()),
            file_conflicts: find_file_conflicts(tasks)
        }
    end
  end

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

  def compute_pipeline(tasks) do
    %{
      total: length(tasks),
      pending: Enum.count(tasks, &(&1.status == "pending")),
      in_progress: Enum.count(tasks, &(&1.status == "in_progress")),
      completed: Enum.count(tasks, &(&1.status == "completed")),
      failed: Enum.count(tasks, &(&1.status == "failed")),
      blocked: Enum.count(tasks, &(&1.status == "blocked"))
    }
  end

  def compute_dag(tasks) do
    completed_ids =
      tasks |> Enum.filter(&(&1.status == "completed")) |> Enum.map(& &1.id) |> MapSet.new()

    task_map = Map.new(tasks, &{&1.id, &1})

    edges =
      Enum.flat_map(tasks, fn task -> Enum.map(task.blocked_by, fn dep -> {dep, task.id} end) end)

    %{
      waves: compute_waves(tasks, task_map),
      edges: edges,
      critical_path: compute_critical_path(tasks, task_map, completed_ids)
    }
  end

  def find_stale_tasks(tasks, now) do
    Enum.filter(tasks, fn task -> task.status == "in_progress" && stale?(task, now, 10) end)
  end

  def find_file_conflicts(tasks) do
    in_progress = Enum.filter(tasks, &(&1.status == "in_progress"))

    for a <- in_progress,
        b <- in_progress,
        a.id < b.id,
        shared = Enum.filter(a.files, fn file -> file in b.files end),
        shared != [] do
      {a.id, b.id, shared}
    end
  end

  def empty_pipeline,
    do: %{total: 0, pending: 0, in_progress: 0, completed: 0, failed: 0, blocked: 0}

  def empty_dag, do: %{waves: [], edges: [], critical_path: []}

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

  defp compute_waves(tasks, task_map) do
    ids = Enum.map(tasks, & &1.id) |> MapSet.new()
    do_compute_waves(tasks, task_map, ids, MapSet.new(), [], 0)
  end

  defp do_compute_waves(tasks, task_map, all_ids, assigned, waves, wave_num) do
    if MapSet.size(assigned) == MapSet.size(all_ids) or wave_num > 50 do
      Enum.reverse(waves)
    else
      wave = tasks |> Enum.filter(&wave_ready?(&1, assigned, all_ids)) |> Enum.map(& &1.id)

      case wave do
        [] ->
          Enum.reverse([collect_remaining_ids(tasks, assigned) | waves])

        _ ->
          new_assigned = Enum.reduce(wave, assigned, &MapSet.put(&2, &1))
          do_compute_waves(tasks, task_map, all_ids, new_assigned, [wave | waves], wave_num + 1)
      end
    end
  end

  defp compute_critical_path(tasks, task_map, _completed_ids) do
    {_memo, lengths} =
      Enum.reduce(tasks, {%{}, %{}}, fn task, {memo, lengths} ->
        {depth, memo} = longest_chain(task.id, task_map, memo)
        {memo, Map.put(lengths, task.id, depth)}
      end)

    case Enum.max_by(lengths, fn {_id, depth} -> depth end, fn -> {nil, 0} end) do
      {nil, _} -> []
      {start_id, _} -> trace_critical_path(start_id, task_map)
    end
  end

  defp longest_chain(id, task_map, memo) do
    case Map.get(memo, id) do
      nil -> compute_chain_depth(id, task_map, memo)
      depth -> {depth, memo}
    end
  end

  defp compute_chain_depth(id, task_map, memo) do
    case Map.get(task_map, id) do
      nil ->
        {0, Map.put(memo, id, 0)}

      task ->
        {max_dep, memo} =
          Enum.reduce(task.blocked_by, {0, memo}, fn dep_id, {max_depth, memo_acc} ->
            {depth, memo_acc} = longest_chain(dep_id, task_map, memo_acc)
            {max(max_depth, depth), memo_acc}
          end)

        depth = max_dep + 1
        {depth, Map.put(memo, id, depth)}
    end
  end

  defp trace_critical_path(id, task_map) do
    case Map.get(task_map, id) do
      nil -> []
      task -> trace_from_task(id, task, task_map)
    end
  end

  defp trace_from_task(id, %{blocked_by: []}, _task_map), do: [id]

  defp trace_from_task(id, %{blocked_by: deps}, task_map) do
    longest_dep =
      deps
      |> Enum.map(&dep_path_length(&1, task_map))
      |> Enum.max_by(fn {_id, len} -> len end)
      |> elem(0)

    trace_critical_path(longest_dep, task_map) ++ [id]
  end

  defp dep_path_length(dep_id, task_map) do
    case Map.get(task_map, dep_id) do
      nil -> {dep_id, 0}
      _ -> {dep_id, length(trace_critical_path(dep_id, task_map))}
    end
  end

  defp wave_ready?(task, assigned, all_ids) do
    not MapSet.member?(assigned, task.id) and
      Enum.all?(task.blocked_by, fn dep ->
        MapSet.member?(assigned, dep) or not MapSet.member?(all_ids, dep)
      end)
  end

  defp collect_remaining_ids(tasks, assigned) do
    tasks |> Enum.reject(fn task -> MapSet.member?(assigned, task.id) end) |> Enum.map(& &1.id)
  end

  defp stale?(task, now, threshold_min) do
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
