defmodule Ichor.Factory.PipelineQuery do
  @moduledoc """
  Pure query module for pipeline board state.

  No process, no GenServer. LiveView callers read directly.
  Discovery and health checks run as Oban cron workers.
  """

  alias Ichor.Factory.{DateUtils, JsonlStore, PipelineGraph}
  alias Ichor.Infrastructure.Cleanup
  alias Ichor.Signals.EventStream

  @teams_dir Path.expand("~/.claude/teams")
  @archive_dir Path.expand("~/.claude/teams/.archive")

  @doc "Computes the full pipeline board state for the given project map and active project key."
  @spec board_state(map(), String.t() | nil) :: map()
  def board_state(watched_projects, active_project) do
    all_tasks =
      watched_projects
      |> Enum.flat_map(fn {key, path} ->
        path
        |> Path.join("tasks.jsonl")
        |> parse_tasks_jsonl()
        |> Enum.map(fn task -> %{task | project: key} end)
      end)

    task_stats =
      case all_tasks do
        [] ->
          %{
            tasks: [],
            pipeline: empty_pipeline(),
            dependency_graph: empty_dependency_graph(),
            stale_tasks: [],
            file_conflicts: []
          }

        tasks ->
          nodes = Enum.map(tasks, &PipelineGraph.to_graph_node/1)

          %{
            tasks: tasks,
            pipeline: PipelineGraph.pipeline_stats(nodes),
            dependency_graph: PipelineGraph.dependency_graph(nodes),
            stale_tasks: find_stale_tasks(tasks, DateTime.utc_now()),
            file_conflicts: file_conflicts(tasks)
          }
      end

    Map.merge(task_stats, %{
      watched_projects: watched_projects,
      active_project: active_project,
      archives: scan_archives()
    })
  end

  @doc "Scans all known discovery directories and returns a project key => path map."
  @spec projects() :: map()
  def projects do
    event_projects = discover_from_events()
    archive_projects = discover_from_archives()
    team_projects = discover_from_teams()

    event_projects
    |> Map.merge(archive_projects)
    |> Map.merge(team_projects)
  end

  @doc "Returns archived team summaries from the archive directory."
  @spec archives() :: list()
  def archives, do: scan_archives()

  @doc "Resets a task to pending status with no owner."
  @spec heal_task(String.t(), String.t()) :: :ok | {:error, term()}
  def heal_task(path, task_id), do: JsonlStore.heal_task(path, task_id)

  @doc "Reassigns a task to a new owner."
  @spec reassign_task(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def reassign_task(path, task_id, new_owner),
    do: JsonlStore.reassign_task(path, task_id, new_owner)

  @doc "Claims a task for an agent, setting it to in_progress."
  @spec claim_task(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def claim_task(task_id, agent_name, path), do: JsonlStore.claim_task(task_id, agent_name, path)

  @doc "Resets all in-progress tasks stale longer than threshold_min minutes."
  @spec reset_all_stale(String.t(), list(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def reset_all_stale(tasks_path, tasks, threshold_min \\ 10) do
    now = DateTime.utc_now()

    reset_count =
      tasks
      |> find_stale_tasks(now)
      |> Enum.filter(&stale_with_threshold?(&1, now, threshold_min))
      |> Enum.count(fn task ->
        JsonlStore.update_task_status(tasks_path, task.id, "pending", "") == :ok
      end)

    {:ok, reset_count}
  end

  @doc "Triggers GC for a named team."
  @spec trigger_gc(String.t(), String.t()) :: :ok | {:error, term()}
  def trigger_gc(team_name, tasks_path), do: Cleanup.trigger_gc(team_name, tasks_path)

  @doc "Parses a tasks.jsonl file, returning normalized task maps (excludes deleted)."
  @spec parse_tasks_jsonl(String.t()) :: list()
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

  @doc "Derives the tasks.jsonl path for a given task within watched_projects."
  @spec tasks_jsonl_path_for_task(map(), map(), String.t() | nil) :: String.t() | nil
  def tasks_jsonl_path_for_task(watched_projects, tasks, task_id) do
    case Enum.find(tasks, fn task -> task.id == task_id end) do
      nil ->
        active_project_tasks_path(watched_projects, nil)

      %{project: project} when project != "" ->
        case Map.get(watched_projects, project) do
          nil -> nil
          path -> Path.join(path, "tasks.jsonl")
        end

      _ ->
        nil
    end
  end

  @doc "Returns the tasks.jsonl path for the active project."
  @spec active_project_tasks_path(map(), String.t() | nil) :: String.t() | nil
  def active_project_tasks_path(_watched_projects, nil), do: nil

  def active_project_tasks_path(watched_projects, key) do
    case Map.get(watched_projects, key) do
      nil -> nil
      path -> Path.join(path, "tasks.jsonl")
    end
  end

  # Discovery internals

  defp discover_from_events do
    EventStream.unique_project_cwds()
    |> Enum.filter(fn cwd -> File.exists?(Path.join(cwd, "tasks.jsonl")) end)
    |> Map.new(fn cwd -> {Path.basename(cwd), cwd} end)
  end

  defp discover_from_teams do
    case File.ls(@teams_dir) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&(&1 == ".archive"))
        |> Enum.reduce(%{}, &collect_project_from_config(&1, @teams_dir, &2))

      _ ->
        %{}
    end
  end

  defp discover_from_archives do
    case File.ls(@archive_dir) do
      {:ok, entries} ->
        Enum.reduce(entries, %{}, &collect_project_from_config(&1, @archive_dir, &2))

      _ ->
        %{}
    end
  end

  defp collect_project_from_config(name, dir, acc) do
    config_path = Path.join([dir, name, "config.json"])

    case read_team_project(config_path) do
      nil -> acc
      project_path -> Map.put(acc, Path.basename(project_path), project_path)
    end
  end

  defp read_team_project(config_path) do
    with {:ok, json} <- File.read(config_path),
         {:ok, config} <- Jason.decode(json) do
      members = config["members"] || []
      Enum.find_value(members, fn m -> m["cwd"] end)
    else
      _ -> nil
    end
  end

  defp scan_archives do
    case File.ls(@archive_dir) do
      {:ok, entries} -> Enum.map(entries, &parse_archive_entry/1)
      _ -> []
    end
  end

  defp parse_archive_entry(name) do
    archive_path = Path.join(@archive_dir, name)
    summary_path = Path.join(archive_path, "gc-summary.json")

    with {:ok, json} <- File.read(summary_path),
         {:ok, summary} <- Jason.decode(json) do
      %{
        team: summary["team"] || name,
        timestamp: summary["archived_at"],
        path: archive_path,
        task_count: get_in(summary, ["task_summary"]) |> total_from_summary()
      }
    else
      _ -> %{team: name, timestamp: nil, path: archive_path, task_count: 0}
    end
  end

  defp total_from_summary(nil), do: 0

  defp total_from_summary(summary) when is_list(summary) do
    Enum.reduce(summary, 0, fn item, acc -> acc + (item["count"] || 0) end)
  end

  defp total_from_summary(_), do: 0

  # Pipeline analysis helpers

  defp find_stale_tasks(tasks, now) do
    tasks
    |> Enum.map(&PipelineGraph.to_graph_node/1)
    |> PipelineGraph.stale_items(now, 10)
    |> Enum.map(fn node -> Enum.find(tasks, &(&1.id == node.id)) end)
  end

  defp file_conflicts(tasks) do
    tasks
    |> Enum.map(&PipelineGraph.to_graph_node/1)
    |> PipelineGraph.file_conflicts()
  end

  defp stale_with_threshold?(task, now, threshold_min) do
    case DateUtils.parse_timestamp(task.updated) do
      nil -> true
      timestamp -> DateTime.diff(now, timestamp, :minute) > threshold_min
    end
  end

  defp empty_pipeline,
    do: %{total: 0, pending: 0, in_progress: 0, completed: 0, failed: 0, blocked: 0}

  defp empty_dependency_graph, do: %{waves: [], edges: [], critical_path: []}

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
end
