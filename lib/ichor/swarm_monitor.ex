defmodule Ichor.SwarmMonitor do
  @moduledoc """
  Monitors swarm/dag pipelines by reading tasks.jsonl from project roots
  and running health-check.sh periodically. Provides action functions for
  healing, reassigning, and garbage-collecting pipelines.
  """
  use GenServer

  alias Ichor.Fleet.Lifecycle.Cleanup
  alias Ichor.SwarmMonitor.Analysis
  alias Ichor.SwarmMonitor.Health
  alias Ichor.Signals.Message
  alias Ichor.SwarmMonitor.Discovery
  alias Ichor.SwarmMonitor.TaskState

  @tasks_poll_interval 3_000
  @health_poll_interval 30_000
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
      manual_projects: %{},
      active_project: first_project_key(projects),
      tasks: [],
      pipeline: %{total: 0, pending: 0, in_progress: 0, completed: 0, failed: 0, blocked: 0},
      dag: %{waves: [], edges: [], critical_path: []},
      stale_tasks: [],
      file_conflicts: [],
      health: %{healthy: true, issues: [], agents: %{}, timestamp: nil},
      monitor_running: false,
      archives: scan_archives(),
      known_cwds: MapSet.new()
    }

    # Auto-discover projects from hook events (session cwds)
    Ichor.Signals.subscribe(:events)

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
      manual = Map.put(state.manual_projects, key, path)
      projects = Map.put(state.watched_projects, key, path)
      state = %{state | manual_projects: manual, watched_projects: projects, active_project: key}
      state = refresh_tasks(state)
      broadcast(state)
      {:reply, :ok, state}
    else
      {:reply, {:error, :path_not_found}, state}
    end
  end

  def handle_call({:heal_task, task_id}, _from, state) do
    case tasks_jsonl_path_for_task(state, task_id) do
      nil ->
        {:reply, {:error, :no_active_project}, state}

      path ->
        result = TaskState.heal_task(path, task_id)
        state = refresh_tasks(state)
        broadcast(state)
        {:reply, result, state}
    end
  end

  def handle_call({:reassign_task, task_id, new_owner}, _from, state) do
    case tasks_jsonl_path_for_task(state, task_id) do
      nil ->
        {:reply, {:error, :no_active_project}, state}

      path ->
        result = TaskState.reassign_task(path, task_id, new_owner)
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
          Analysis.find_stale_tasks(state.tasks, now)
          |> Enum.filter(fn task -> stale_with_threshold?(task, now, threshold_min) end)
          |> Enum.reduce(0, &count_reset(&1, &2, path))

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
        result = Cleanup.trigger_gc(team_name, path)

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
    case tasks_jsonl_path_for_task(state, task_id) do
      nil ->
        {:reply, {:error, :no_active_project}, state}

      path ->
        result = TaskState.claim_task(task_id, agent_name, path)
        state = refresh_tasks(state)
        broadcast(state)
        {:reply, result, state}
    end
  end

  # Auto-discover projects from hook event cwds
  def handle_info(%Message{name: :new_event, data: %{event: event}}, state) do
    cwd = event.cwd

    if is_binary(cwd) and cwd != "" and not MapSet.member?(state.known_cwds, cwd) do
      new_cwds = MapSet.put(state.known_cwds, cwd)
      key = Path.basename(cwd)
      tasks_path = Path.join(cwd, "tasks.jsonl")

      if File.exists?(tasks_path) and not Map.has_key?(state.watched_projects, key) do
        projects = Map.put(state.watched_projects, key, cwd)
        active = state.active_project || key

        state = %{
          state
          | watched_projects: projects,
            active_project: active,
            known_cwds: new_cwds
        }

        state = refresh_tasks(state)
        broadcast(state)
        {:noreply, state}
      else
        {:noreply, %{state | known_cwds: new_cwds}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:poll_tasks, state) do
    Process.send_after(self(), :poll_tasks, @tasks_poll_interval)

    # Re-discover projects on each poll (cheap: reads team config dir).
    # Merge manual_projects last so user additions survive team deletions,
    # but discovered projects that disappear from disk are dropped.
    new_projects = Map.merge(discover_projects(), state.manual_projects)

    state =
      if new_projects != state.watched_projects do
        active =
          if state.active_project && Map.has_key?(new_projects, state.active_project),
            do: state.active_project,
            else: first_project_key(new_projects)

        %{state | watched_projects: new_projects, active_project: active}
      else
        state
      end

    old_tasks = state.tasks
    state = refresh_tasks(state)

    if state.tasks != old_tasks || new_projects != state.watched_projects do
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
    Analysis.refresh_tasks(state)
  end

  # ═══════════════════════════════════════════════════════
  # Health
  # ═══════════════════════════════════════════════════════

  defp do_health_check(state) do
    Health.run(state, get_active_project_path(state))
  end

  defp count_reset(task, acc, path) do
    case TaskState.update_task_status(path, task.id, "pending", "") do
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

  # ═══════════════════════════════════════════════════════
  # Project discovery (delegated to SwarmMonitor.Discovery)
  # ═══════════════════════════════════════════════════════

  defp discover_projects, do: Discovery.discover_projects()
  defp scan_archives, do: Discovery.scan_archives()

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp tasks_jsonl_path(state) do
    case get_active_project_path(state) do
      nil -> nil
      path -> Path.join(path, "tasks.jsonl")
    end
  end

  # Find the tasks.jsonl path for a specific task by looking up its project
  defp tasks_jsonl_path_for_task(state, task_id) do
    case Enum.find(state.tasks, fn t -> t.id == task_id end) do
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

  defp get_active_project_path(state) do
    case state.active_project do
      nil -> nil
      key -> Map.get(state.watched_projects, key)
    end
  end

  defp first_project_key(projects) when map_size(projects) == 0, do: nil
  defp first_project_key(projects), do: projects |> Map.keys() |> hd()

  defp broadcast(state) do
    Ichor.Signals.emit(:swarm_state, %{state_map: state})
  end
end
