defmodule Ichor.Projects.Runtime do
  @moduledoc """
  Live DAG pipeline runtime.

  This is the active GenServer behind project discovery, task refresh,
  health polling, and corrective task actions for `tasks.jsonl` pipelines.

  Incorporates: Actions, Catalog, DagAnalysis, Discovery, HealthReport.
  """
  use GenServer

  require Logger

  alias Ichor.Control.Lifecycle.Cleanup
  alias Ichor.EventBuffer
  alias Ichor.Projects.{DateUtils, Graph}
  alias Ichor.Signals.Message
  alias Ichor.Tasks.JsonlStore

  @tasks_poll_interval 3_000
  @health_poll_interval 30_000

  @teams_dir Path.expand("~/.claude/teams")
  @archive_dir Path.expand("~/.claude/teams/.archive")
  @health_check_script Path.expand("~/.claude/skills/swarm/scripts/health-check.sh")

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Returns the current DAG runtime state map."
  @spec state() :: map()
  def state, do: GenServer.call(__MODULE__, :get_state)

  @doc "Switches the active project to the given key."
  @spec set_active_project(String.t()) :: :ok | {:error, term()}
  def set_active_project(project_key),
    do: GenServer.call(__MODULE__, {:set_active_project, project_key})

  @doc "Registers a project at the given path under key."
  @spec add_project(String.t(), String.t()) :: :ok | {:error, term()}
  def add_project(key, path),
    do: GenServer.call(__MODULE__, {:add_project, key, path})

  @doc "Resets a stale or failed task back to pending."
  @spec heal_task(String.t()) :: :ok | {:error, term()}
  def heal_task(task_id),
    do: GenServer.call(__MODULE__, {:heal_task, task_id})

  @doc "Reassigns a task to a new owner."
  @spec reassign_task(String.t(), String.t()) :: :ok | {:error, term()}
  def reassign_task(task_id, new_owner),
    do: GenServer.call(__MODULE__, {:reassign_task, task_id, new_owner})

  @doc "Resets all in-progress tasks stale longer than threshold_min minutes."
  @spec reset_all_stale(non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def reset_all_stale(threshold_min \\ 10),
    do: GenServer.call(__MODULE__, {:reset_all_stale, threshold_min})

  @doc "Triggers GC for a named team, archiving completed work."
  @spec trigger_gc(String.t()) :: :ok | {:error, term()}
  def trigger_gc(team_name),
    do: GenServer.call(__MODULE__, {:trigger_gc, team_name}, 15_000)

  @doc "Runs a health check immediately and broadcasts the result."
  @spec run_health_check() :: :ok
  def run_health_check,
    do: GenServer.call(__MODULE__, :run_health_check, 15_000)

  @doc "Claims a task for an agent, setting it to in_progress."
  @spec claim_task(String.t(), String.t()) :: :ok | {:error, term()}
  def claim_task(task_id, agent_name),
    do: GenServer.call(__MODULE__, {:claim_task, task_id, agent_name})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    project_state = initial_state()

    state =
      %{
        tasks: [],
        pipeline: %{total: 0, pending: 0, in_progress: 0, completed: 0, failed: 0, blocked: 0},
        dag: %{waves: [], edges: [], critical_path: []},
        stale_tasks: [],
        file_conflicts: [],
        health: %{healthy: true, issues: [], agents: %{}, timestamp: nil},
        monitor_running: false
      }
      |> Map.merge(project_state)

    Ichor.Signals.subscribe(:events)

    send(self(), :poll_tasks)
    Process.send_after(self(), :poll_health, 5_000)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call({:set_active_project, key}, _from, state) do
    case set_active_project_in_state(state, key) do
      {:ok, next_state} ->
        next_state = refresh_tasks(next_state)
        broadcast(next_state)
        {:reply, :ok, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:add_project, key, path}, _from, state) do
    case add_project_to_state(state, key, path) do
      {:ok, next_state} ->
        next_state = refresh_tasks(next_state)
        broadcast(next_state)
        {:reply, :ok, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:heal_task, task_id}, _from, state) do
    result = heal_task_in_state(state, task_id)
    next_state = refresh_tasks(state)
    broadcast(next_state)
    {:reply, result, next_state}
  end

  def handle_call({:reassign_task, task_id, new_owner}, _from, state) do
    result = reassign_task_in_state(state, task_id, new_owner)
    next_state = refresh_tasks(state)
    broadcast(next_state)
    {:reply, result, next_state}
  end

  def handle_call({:reset_all_stale, threshold_min}, _from, state) do
    result = reset_all_stale_in_state(state, threshold_min)
    next_state = refresh_tasks(state)
    broadcast(next_state)
    {:reply, result, next_state}
  end

  def handle_call({:trigger_gc, team_name}, _from, state) do
    result = trigger_gc_in_state(state, team_name)
    next_state = %{state | archives: scan_archives()}
    broadcast(next_state)
    {:reply, result, next_state}
  end

  def handle_call(:run_health_check, _from, state) do
    next_state = do_health_check(state)
    broadcast(next_state)
    {:reply, :ok, next_state}
  end

  def handle_call({:claim_task, task_id, agent_name}, _from, state) do
    result = claim_task_in_state(state, task_id, agent_name)
    next_state = refresh_tasks(state)
    broadcast(next_state)
    {:reply, result, next_state}
  end

  def handle_info(%Message{name: :new_event, data: %{event: event}}, state) do
    {next_state, changed?} = register_cwd(state, event.cwd)

    if changed? do
      refreshed = refresh_tasks(next_state)
      broadcast(refreshed)
      {:noreply, refreshed}
    else
      {:noreply, next_state}
    end
  end

  @impl true
  def handle_info(:poll_tasks, state) do
    Process.send_after(self(), :poll_tasks, @tasks_poll_interval)

    {next_state, projects_changed?} = refresh_discovered_projects(state)
    old_tasks = next_state.tasks
    refreshed = refresh_tasks(next_state)

    if refreshed.tasks != old_tasks || projects_changed? do
      broadcast(refreshed)
    end

    {:noreply, refreshed}
  end

  def handle_info(:poll_health, state) do
    Process.send_after(self(), :poll_health, @health_poll_interval)
    next_state = do_health_check(state)
    broadcast(next_state)
    {:noreply, next_state}
  end

  defp broadcast(state), do: Ichor.Signals.emit(:dag_status, %{state_map: state})

  # ---------------------------------------------------------------------------
  # Catalog (formerly Ichor.Projects.Catalog)
  # ---------------------------------------------------------------------------

  defp initial_state do
    projects = discover_projects()

    %{
      watched_projects: projects,
      manual_projects: %{},
      active_project: first_project_key(projects),
      known_cwds: MapSet.new(),
      archives: scan_archives()
    }
  end

  defp set_active_project_in_state(state, key) do
    if Map.has_key?(state.watched_projects, key) do
      {:ok, %{state | active_project: key}}
    else
      {:error, :unknown_project}
    end
  end

  defp add_project_to_state(state, key, path) do
    tasks_path = Path.join(path, "tasks.jsonl")

    if File.exists?(tasks_path) or File.dir?(path) do
      manual = Map.put(state.manual_projects, key, path)
      projects = Map.put(state.watched_projects, key, path)

      {:ok, %{state | manual_projects: manual, watched_projects: projects, active_project: key}}
    else
      {:error, :path_not_found}
    end
  end

  defp refresh_discovered_projects(state) do
    new_projects = Map.merge(discover_projects(), state.manual_projects)

    if new_projects != state.watched_projects do
      active =
        if state.active_project && Map.has_key?(new_projects, state.active_project),
          do: state.active_project,
          else: first_project_key(new_projects)

      {%{state | watched_projects: new_projects, active_project: active}, true}
    else
      {state, false}
    end
  end

  defp register_cwd(state, cwd) when is_binary(cwd) and cwd != "" do
    if MapSet.member?(state.known_cwds, cwd) do
      {state, false}
    else
      new_cwds = MapSet.put(state.known_cwds, cwd)
      key = Path.basename(cwd)
      tasks_path = Path.join(cwd, "tasks.jsonl")

      if File.exists?(tasks_path) and not Map.has_key?(state.watched_projects, key) do
        projects = Map.put(state.watched_projects, key, cwd)
        active = state.active_project || key

        {%{state | watched_projects: projects, active_project: active, known_cwds: new_cwds},
         true}
      else
        {%{state | known_cwds: new_cwds}, false}
      end
    end
  end

  defp register_cwd(state, _cwd), do: {state, false}

  defp tasks_jsonl_path(state) do
    case active_project_path(state) do
      nil -> nil
      path -> Path.join(path, "tasks.jsonl")
    end
  end

  defp tasks_jsonl_path_for_task(state, task_id) do
    case Enum.find(state.tasks, fn task -> task.id == task_id end) do
      nil ->
        tasks_jsonl_path(state)

      %{project: project} when project != "" ->
        case Map.get(state.watched_projects, project) do
          nil -> tasks_jsonl_path(state)
          path -> Path.join(path, "tasks.jsonl")
        end

      _ ->
        tasks_jsonl_path(state)
    end
  end

  defp active_project_path(state) do
    case state.active_project do
      nil -> nil
      key -> Map.get(state.watched_projects, key)
    end
  end

  defp first_project_key(projects) when map_size(projects) == 0, do: nil
  defp first_project_key(projects), do: projects |> Map.keys() |> hd()

  # ---------------------------------------------------------------------------
  # Actions (formerly Ichor.Projects.Actions)
  # ---------------------------------------------------------------------------

  defp heal_task_in_state(state, task_id) do
    case tasks_jsonl_path_for_task(state, task_id) do
      nil -> {:error, :no_active_project}
      path -> JsonlStore.heal_task(path, task_id)
    end
  end

  defp reassign_task_in_state(state, task_id, new_owner) do
    case tasks_jsonl_path_for_task(state, task_id) do
      nil -> {:error, :no_active_project}
      path -> JsonlStore.reassign_task(path, task_id, new_owner)
    end
  end

  defp claim_task_in_state(state, task_id, agent_name) do
    case tasks_jsonl_path_for_task(state, task_id) do
      nil -> {:error, :no_active_project}
      path -> JsonlStore.claim_task(task_id, agent_name, path)
    end
  end

  defp reset_all_stale_in_state(state, threshold_min) do
    case tasks_jsonl_path(state) do
      nil ->
        {:error, :no_active_project}

      path ->
        now = DateTime.utc_now()

        reset_count =
          find_stale_tasks(state.tasks, now)
          |> Enum.filter(fn task -> stale_with_threshold?(task, now, threshold_min) end)
          |> Enum.reduce(0, &count_reset(&1, &2, path))

        {:ok, reset_count}
    end
  end

  defp trigger_gc_in_state(state, team_name) do
    case tasks_jsonl_path(state) do
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
    case DateUtils.parse_timestamp(task.updated) do
      nil -> true
      timestamp -> DateTime.diff(now, timestamp, :minute) > threshold_min
    end
  end

  # ---------------------------------------------------------------------------
  # DagAnalysis (formerly Ichor.Projects.DagAnalysis)
  # ---------------------------------------------------------------------------

  defp refresh_tasks(state) do
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
            stale_tasks: find_stale_tasks(tasks, DateTime.utc_now()),
            file_conflicts: file_conflicts(tasks)
        }
    end
  end

  defp parse_tasks_jsonl(path) do
    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.map(&decode_task_line/1)
      |> Enum.reject(fn task -> is_nil(task) or task.status == "deleted" end)
    else
      []
    end
  end

  defp find_stale_tasks(tasks, now) do
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

  # ---------------------------------------------------------------------------
  # Discovery (formerly Ichor.Projects.Discovery)
  # ---------------------------------------------------------------------------

  defp discover_projects do
    event_projects = discover_from_events()
    archive_projects = discover_from_archives()
    team_projects = discover_from_teams()

    event_projects
    |> Map.merge(archive_projects)
    |> Map.merge(team_projects)
  end

  defp scan_archives do
    case File.ls(@archive_dir) do
      {:ok, entries} -> Enum.map(entries, &parse_archive_entry/1)
      _ -> []
    end
  end

  defp discover_from_events do
    EventBuffer.unique_project_cwds()
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

  # ---------------------------------------------------------------------------
  # HealthReport (formerly Ichor.Projects.HealthReport)
  # ---------------------------------------------------------------------------

  defp do_health_check(state) do
    project_path = active_project_path(state)

    if project_path && File.exists?(@health_check_script) do
      case run_health_script(project_path) do
        {:ok, health} -> %{state | health: health}
        :error -> state
      end
    else
      state
    end
  end

  defp run_health_script(project_path) do
    case System.cmd("bash", [@health_check_script, project_path, "10"],
           stderr_to_stdout: true,
           env: []
         ) do
      {output, 0} -> parse_health_output(output)
      {_output, _code} -> :error
    end
  end

  defp parse_health_output(output) do
    case Jason.decode(output) do
      {:ok, report} ->
        {:ok,
         %{
           healthy: report["healthy"] || false,
           issues: parse_health_issues(report),
           agents: report["agents"] || %{},
           timestamp: DateTime.utc_now()
         }}

      _ ->
        Logger.warning("DAG runtime: Failed to parse health report")
        :error
    end
  end

  defp parse_health_issues(report) do
    (get_in(report, ["issues", "details"]) || [])
    |> Enum.map(fn issue ->
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
end
