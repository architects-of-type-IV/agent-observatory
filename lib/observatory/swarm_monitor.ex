defmodule Observatory.SwarmMonitor do
  @moduledoc """
  Monitors swarm/dag pipelines by reading tasks.jsonl from project roots
  and running health-check.sh periodically. Provides action functions for
  healing, reassigning, and garbage-collecting pipelines.
  """
  use GenServer
  require Logger

  @tasks_poll_interval 3_000
  @health_poll_interval 30_000
  @health_check_script Path.expand("~/.claude/skills/swarm/scripts/health-check.sh")
  @teams_dir Path.expand("~/.claude/teams")
  @archive_dir Path.expand("~/.claude/teams/.archive")

  # ═══════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def get_state, do: GenServer.call(__MODULE__, :get_state)

  def set_active_project(project_key),
    do: GenServer.call(__MODULE__, {:set_active_project, project_key})

  def add_project(key, path),
    do: GenServer.call(__MODULE__, {:add_project, key, path})

  def heal_task(task_id),
    do: GenServer.call(__MODULE__, {:heal_task, task_id})

  def reassign_task(task_id, new_owner),
    do: GenServer.call(__MODULE__, {:reassign_task, task_id, new_owner})

  def reset_all_stale(threshold_min \\ 10),
    do: GenServer.call(__MODULE__, {:reset_all_stale, threshold_min})

  def trigger_gc(team_name),
    do: GenServer.call(__MODULE__, {:trigger_gc, team_name}, 15_000)

  def run_health_check,
    do: GenServer.call(__MODULE__, :run_health_check, 15_000)

  def claim_task(task_id, agent_name),
    do: GenServer.call(__MODULE__, {:claim_task, task_id, agent_name})

  # ═══════════════════════════════════════════════════════
  # Server
  # ═══════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    projects = discover_projects()

    state = %{
      watched_projects: projects,
      active_project: first_project_key(projects),
      tasks: [],
      pipeline: %{total: 0, pending: 0, in_progress: 0, completed: 0, failed: 0, blocked: 0},
      dag: %{waves: [], edges: [], critical_path: []},
      stale_tasks: [],
      file_conflicts: [],
      health: %{healthy: true, issues: [], agents: %{}, timestamp: nil},
      monitor_running: false,
      archives: scan_archives()
    }

    send(self(), :poll_tasks)
    Process.send_after(self(), :poll_health, 5_000)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:set_active_project, key}, _from, state) do
    if Map.has_key?(state.watched_projects, key) do
      state = %{state | active_project: key}
      state = refresh_tasks(state)
      broadcast(state)
      {:reply, :ok, state}
    else
      {:reply, {:error, :unknown_project}, state}
    end
  end

  def handle_call({:add_project, key, path}, _from, state) do
    tasks_path = Path.join(path, "tasks.jsonl")

    if File.exists?(tasks_path) or File.dir?(path) do
      projects = Map.put(state.watched_projects, key, path)
      state = %{state | watched_projects: projects, active_project: key}
      state = refresh_tasks(state)
      broadcast(state)
      {:reply, :ok, state}
    else
      {:reply, {:error, :path_not_found}, state}
    end
  end

  def handle_call({:heal_task, task_id}, _from, state) do
    case tasks_jsonl_path(state) do
      nil ->
        {:reply, {:error, :no_active_project}, state}

      path ->
        result = jq_update_task(path, task_id, "pending", "")
        state = refresh_tasks(state)
        broadcast(state)
        {:reply, result, state}
    end
  end

  def handle_call({:reassign_task, task_id, new_owner}, _from, state) do
    case tasks_jsonl_path(state) do
      nil ->
        {:reply, {:error, :no_active_project}, state}

      path ->
        result = jq_reassign_task(path, task_id, new_owner)
        state = refresh_tasks(state)
        broadcast(state)
        {:reply, result, state}
    end
  end

  def handle_call({:reset_all_stale, threshold_min}, _from, state) do
    case tasks_jsonl_path(state) do
      nil ->
        {:reply, {:error, :no_active_project}, state}

      path ->
        now = DateTime.utc_now()

        reset_count =
          state.tasks
          |> Enum.filter(fn t ->
            t.status == "in_progress" && stale?(t, now, threshold_min)
          end)
          |> Enum.reduce(0, fn t, acc ->
            case jq_update_task(path, t.id, "pending", "") do
              :ok -> acc + 1
              _ -> acc
            end
          end)

        state = refresh_tasks(state)
        broadcast(state)
        {:reply, {:ok, reset_count}, state}
    end
  end

  def handle_call({:trigger_gc, team_name}, _from, state) do
    case tasks_jsonl_path(state) do
      nil ->
        {:reply, {:error, :no_active_project}, state}

      path ->
        gc_script = Path.expand("~/.claude/skills/dag/scripts/gc.sh")

        result =
          case System.cmd("bash", [gc_script, team_name, path],
                 stderr_to_stdout: true,
                 env: []
               ) do
            {output, 0} -> {:ok, String.trim(output)}
            {output, _} -> {:error, String.trim(output)}
          end

        state = %{state | archives: scan_archives()}
        broadcast(state)
        {:reply, result, state}
    end
  end

  def handle_call(:run_health_check, _from, state) do
    state = do_health_check(state)
    broadcast(state)
    {:reply, :ok, state}
  end

  def handle_call({:claim_task, task_id, agent_name}, _from, state) do
    case tasks_jsonl_path(state) do
      nil ->
        {:reply, {:error, :no_active_project}, state}

      path ->
        claim_script = Path.expand("~/.claude/skills/dag/scripts/claim-task.sh")

        result =
          case System.cmd("bash", [claim_script, task_id, agent_name, path],
                 stderr_to_stdout: true,
                 env: []
               ) do
            {output, 0} ->
              if String.contains?(output, "CLAIMED"), do: :ok, else: {:error, String.trim(output)}

            {output, _} ->
              {:error, String.trim(output)}
          end

        state = refresh_tasks(state)
        broadcast(state)
        {:reply, result, state}
    end
  end

  @impl true
  def handle_info(:poll_tasks, state) do
    Process.send_after(self(), :poll_tasks, @tasks_poll_interval)
    old_tasks = state.tasks
    state = refresh_tasks(state)

    if state.tasks != old_tasks do
      broadcast(state)
    end

    {:noreply, state}
  end

  def handle_info(:poll_health, state) do
    Process.send_after(self(), :poll_health, @health_poll_interval)
    state = do_health_check(state)
    broadcast(state)
    {:noreply, state}
  end

  # ═══════════════════════════════════════════════════════
  # Tasks parsing
  # ═══════════════════════════════════════════════════════

  defp refresh_tasks(state) do
    case tasks_jsonl_path(state) do
      nil ->
        %{
          state
          | tasks: [],
            pipeline: empty_pipeline(),
            dag: empty_dag(),
            stale_tasks: [],
            file_conflicts: []
        }

      path ->
        tasks = parse_tasks_jsonl(path)
        pipeline = compute_pipeline(tasks)
        dag = compute_dag(tasks)
        stale = find_stale_tasks(tasks, DateTime.utc_now())
        conflicts = find_file_conflicts(tasks)

        %{
          state
          | tasks: tasks,
            pipeline: pipeline,
            dag: dag,
            stale_tasks: stale,
            file_conflicts: conflicts
        }
    end
  end

  defp parse_tasks_jsonl(path) do
    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.map(fn line ->
        case Jason.decode(String.trim(line)) do
          {:ok, task} -> normalize_task(task)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(fn t -> t.status == "deleted" end)
    else
      []
    end
  end

  defp normalize_task(t) do
    %{
      id: t["id"] || "",
      status: t["status"] || "pending",
      subject: t["subject"] || "",
      description: t["description"] || "",
      owner: t["owner"] || "",
      priority: t["priority"] || "medium",
      blocked_by: t["blocked_by"] || [],
      files: t["files"] || [],
      done_when: t["done_when"] || "",
      updated: t["updated"] || t["created"] || "",
      notes: t["notes"] || "",
      tags: t["tags"] || []
    }
  end

  defp compute_pipeline(tasks) do
    %{
      total: length(tasks),
      pending: Enum.count(tasks, &(&1.status == "pending")),
      in_progress: Enum.count(tasks, &(&1.status == "in_progress")),
      completed: Enum.count(tasks, &(&1.status == "completed")),
      failed: Enum.count(tasks, &(&1.status == "failed")),
      blocked: Enum.count(tasks, &(&1.status == "blocked"))
    }
  end

  # ═══════════════════════════════════════════════════════
  # DAG computation
  # ═══════════════════════════════════════════════════════

  defp compute_dag(tasks) do
    completed_ids =
      tasks |> Enum.filter(&(&1.status == "completed")) |> Enum.map(& &1.id) |> MapSet.new()

    task_map = Map.new(tasks, &{&1.id, &1})

    # Build edges: {blocker_id, dependent_id}
    edges =
      Enum.flat_map(tasks, fn t ->
        Enum.map(t.blocked_by, fn dep -> {dep, t.id} end)
      end)

    # Compute waves via topological sort
    waves = compute_waves(tasks, task_map)

    # Critical path: longest dependency chain
    critical_path = compute_critical_path(tasks, task_map, completed_ids)

    %{waves: waves, edges: edges, critical_path: critical_path}
  end

  defp compute_waves(tasks, task_map) do
    # Wave 0: tasks with no dependencies
    # Wave N: tasks whose all dependencies are in waves < N
    ids = Enum.map(tasks, & &1.id) |> MapSet.new()
    assigned = MapSet.new()
    do_compute_waves(tasks, task_map, ids, assigned, [], 0)
  end

  defp do_compute_waves(tasks, task_map, all_ids, assigned, waves, wave_num) do
    if MapSet.size(assigned) == MapSet.size(all_ids) or wave_num > 50 do
      Enum.reverse(waves)
    else
      wave =
        tasks
        |> Enum.filter(fn t ->
          not MapSet.member?(assigned, t.id) and
            Enum.all?(t.blocked_by, fn dep ->
              MapSet.member?(assigned, dep) or not MapSet.member?(all_ids, dep)
            end)
        end)
        |> Enum.map(& &1.id)

      case wave do
        [] ->
          # Remaining tasks have circular deps or missing deps, put them all in final wave
          remaining =
            Enum.reject(tasks, fn t -> MapSet.member?(assigned, t.id) end) |> Enum.map(& &1.id)

          Enum.reverse([remaining | waves])

        _ ->
          new_assigned = Enum.reduce(wave, assigned, &MapSet.put(&2, &1))
          do_compute_waves(tasks, task_map, all_ids, new_assigned, [wave | waves], wave_num + 1)
      end
    end
  end

  defp compute_critical_path(tasks, task_map, _completed_ids) do
    # DFS to find longest dependency chain
    memo = %{}

    {_memo, lengths} =
      Enum.reduce(tasks, {memo, %{}}, fn t, {m, l} ->
        {depth, m} = longest_chain(t.id, task_map, m)
        {m, Map.put(l, t.id, depth)}
      end)

    case Enum.max_by(lengths, fn {_id, depth} -> depth end, fn -> {nil, 0} end) do
      {nil, _} -> []
      {start_id, _} -> trace_critical_path(start_id, task_map)
    end
  end

  defp longest_chain(id, task_map, memo) do
    case Map.get(memo, id) do
      nil ->
        case Map.get(task_map, id) do
          nil ->
            {0, Map.put(memo, id, 0)}

          task ->
            {max_dep, memo} =
              Enum.reduce(task.blocked_by, {0, memo}, fn dep_id, {max, m} ->
                {depth, m} = longest_chain(dep_id, task_map, m)
                {max(max, depth), m}
              end)

            depth = max_dep + 1
            {depth, Map.put(memo, id, depth)}
        end

      depth ->
        {depth, memo}
    end
  end

  defp trace_critical_path(id, task_map) do
    case Map.get(task_map, id) do
      nil ->
        []

      task ->
        case task.blocked_by do
          [] ->
            [id]

          deps ->
            # Follow the longest dependency
            longest_dep =
              deps
              |> Enum.map(fn dep_id ->
                case Map.get(task_map, dep_id) do
                  nil -> {dep_id, 0}
                  _ -> {dep_id, length(trace_critical_path(dep_id, task_map))}
                end
              end)
              |> Enum.max_by(fn {_id, len} -> len end)
              |> elem(0)

            trace_critical_path(longest_dep, task_map) ++ [id]
        end
    end
  end

  # ═══════════════════════════════════════════════════════
  # Health
  # ═══════════════════════════════════════════════════════

  defp do_health_check(state) do
    project_path = get_active_project_path(state)

    if project_path && File.exists?(@health_check_script) do
      case System.cmd("bash", [@health_check_script, project_path, "10"],
             stderr_to_stdout: true,
             env: []
           ) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, report} ->
              health = %{
                healthy: report["healthy"] || false,
                issues: parse_issues(report),
                agents: report["agents"] || %{},
                timestamp: DateTime.utc_now()
              }

              %{state | health: health}

            _ ->
              Logger.warning("SwarmMonitor: Failed to parse health report")
              state
          end

        {_output, _code} ->
          state
      end
    else
      state
    end
  end

  defp parse_issues(report) do
    details = get_in(report, ["issues", "details"]) || []

    Enum.map(details, fn issue ->
      %{
        type: issue["type"] || "unknown",
        severity: issue["severity"] || "LOW",
        task_id: issue["task_id"],
        owner: issue["owner"],
        description: issue["description"] || "",
        details: issue
      }
    end)
  end

  # ═══════════════════════════════════════════════════════
  # Stale / conflict detection
  # ═══════════════════════════════════════════════════════

  defp find_stale_tasks(tasks, now) do
    tasks
    |> Enum.filter(fn t -> t.status == "in_progress" && stale?(t, now, 10) end)
  end

  defp stale?(task, now, threshold_min) do
    case parse_timestamp(task.updated) do
      nil -> true
      ts -> DateTime.diff(now, ts, :minute) > threshold_min
    end
  end

  defp parse_timestamp(""), do: nil

  defp parse_timestamp(str) when is_binary(str) do
    str = String.replace(str, "Z", "")

    case DateTime.from_iso8601(str <> "Z") do
      {:ok, dt, _} ->
        dt

      _ ->
        case NaiveDateTime.from_iso8601(str) do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp parse_timestamp(_), do: nil

  defp find_file_conflicts(tasks) do
    in_progress = Enum.filter(tasks, &(&1.status == "in_progress"))

    for a <- in_progress,
        b <- in_progress,
        a.id < b.id,
        shared = Enum.filter(a.files, fn f -> f in b.files end),
        shared != [] do
      {a.id, b.id, shared}
    end
  end

  # ═══════════════════════════════════════════════════════
  # Task mutation via jq
  # ═══════════════════════════════════════════════════════

  defp jq_update_task(path, task_id, new_status, new_owner) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    jq_expr =
      ~s(if .id == "#{task_id}" then .status = "#{new_status}" | .owner = "#{new_owner}" | .updated = "#{now}" else . end)

    jq_in_place(path, jq_expr)
  end

  defp jq_reassign_task(path, task_id, new_owner) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    jq_expr =
      ~s(if .id == "#{task_id}" then .owner = "#{new_owner}" | .updated = "#{now}" else . end)

    jq_in_place(path, jq_expr)
  end

  defp jq_in_place(path, expr) do
    tmp = path <> ".tmp"

    case System.cmd("jq", ["-c", expr, path], stderr_to_stdout: true) do
      {output, 0} ->
        case File.write(tmp, output) do
          :ok ->
            File.rename!(tmp, path)
            :ok

          err ->
            File.rm(tmp)
            err
        end

      {err, _} ->
        {:error, err}
    end
  end

  # ═══════════════════════════════════════════════════════
  # Project discovery
  # ═══════════════════════════════════════════════════════

  defp discover_projects do
    team_projects = discover_from_teams()
    archive_projects = discover_from_archives()

    Map.merge(archive_projects, team_projects)
  end

  defp discover_from_teams do
    case File.ls(@teams_dir) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&(&1 == ".archive"))
        |> Enum.reduce(%{}, fn name, acc ->
          config_path = Path.join([@teams_dir, name, "config.json"])

          case read_team_project(config_path) do
            nil -> acc
            project_path -> Map.put(acc, Path.basename(project_path), project_path)
          end
        end)

      _ ->
        %{}
    end
  end

  defp discover_from_archives do
    case File.ls(@archive_dir) do
      {:ok, entries} ->
        entries
        |> Enum.reduce(%{}, fn name, acc ->
          config_path = Path.join([@archive_dir, name, "config.json"])

          case read_team_project(config_path) do
            nil -> acc
            project_path -> Map.put(acc, Path.basename(project_path), project_path)
          end
        end)

      _ ->
        %{}
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
      {:ok, entries} ->
        entries
        |> Enum.map(fn name ->
          archive_path = Path.join(@archive_dir, name)
          summary_path = Path.join(archive_path, "gc-summary.json")

          case File.read(summary_path) do
            {:ok, json} ->
              case Jason.decode(json) do
                {:ok, summary} ->
                  %{
                    team: summary["team"] || name,
                    timestamp: summary["archived_at"],
                    path: archive_path,
                    task_count: get_in(summary, ["task_summary"]) |> total_from_summary()
                  }

                _ ->
                  %{team: name, timestamp: nil, path: archive_path, task_count: 0}
              end

            _ ->
              %{team: name, timestamp: nil, path: archive_path, task_count: 0}
          end
        end)

      _ ->
        []
    end
  end

  defp total_from_summary(nil), do: 0

  defp total_from_summary(summary) when is_list(summary) do
    Enum.reduce(summary, 0, fn item, acc -> acc + (item["count"] || 0) end)
  end

  defp total_from_summary(_), do: 0

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp tasks_jsonl_path(state) do
    case get_active_project_path(state) do
      nil -> nil
      path -> Path.join(path, "tasks.jsonl")
    end
  end

  defp get_active_project_path(state) do
    case state.active_project do
      nil -> nil
      key -> Map.get(state.watched_projects, key)
    end
  end

  defp first_project_key(projects) when map_size(projects) == 0, do: nil
  defp first_project_key(projects), do: projects |> Map.keys() |> hd()

  defp empty_pipeline,
    do: %{total: 0, pending: 0, in_progress: 0, completed: 0, failed: 0, blocked: 0}

  defp empty_dag, do: %{waves: [], edges: [], critical_path: []}

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "swarm:update",
      {:swarm_state, state}
    )
  end
end
