defmodule Ichor.SwarmMonitor do
  @moduledoc """
  Monitors swarm/dag pipelines by reading tasks.jsonl from project roots
  and running health-check.sh periodically. Provides action functions for
  healing, reassigning, and garbage-collecting pipelines.
  """
  use GenServer

  alias Ichor.SwarmMonitor.Actions
  alias Ichor.SwarmMonitor.Analysis
  alias Ichor.SwarmMonitor.Health
  alias Ichor.SwarmMonitor.Discovery
  alias Ichor.SwarmMonitor.Projects
  alias Ichor.SwarmMonitor.StateBus
  alias Ichor.Signals.Message

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
    project_state = Projects.initial_state()

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
    case Projects.set_active_project(state, key) do
      {:ok, state} ->
        state = refresh_tasks(state)
        broadcast(state)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:add_project, key, path}, _from, state) do
    case Projects.add_project(state, key, path) do
      {:ok, state} ->
        state = refresh_tasks(state)
        broadcast(state)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:heal_task, task_id}, _from, state) do
    result = Actions.heal_task(state, task_id)
    state = refresh_tasks(state)
    broadcast(state)
    {:reply, result, state}
  end

  def handle_call({:reassign_task, task_id, new_owner}, _from, state) do
    result = Actions.reassign_task(state, task_id, new_owner)
    state = refresh_tasks(state)
    broadcast(state)
    {:reply, result, state}
  end

  def handle_call({:reset_all_stale, threshold_min}, _from, state) do
    result = Actions.reset_all_stale(state, threshold_min)
    state = refresh_tasks(state)
    broadcast(state)
    {:reply, result, state}
  end

  def handle_call({:trigger_gc, team_name}, _from, state) do
    result = Actions.trigger_gc(state, team_name)

    state = %{state | archives: scan_archives()}
    broadcast(state)
    {:reply, result, state}
  end

  def handle_call(:run_health_check, _from, state) do
    state = do_health_check(state)
    broadcast(state)
    {:reply, :ok, state}
  end

  def handle_call({:claim_task, task_id, agent_name}, _from, state) do
    result = Actions.claim_task(state, task_id, agent_name)
    state = refresh_tasks(state)
    broadcast(state)
    {:reply, result, state}
  end

  # Auto-discover projects from hook event cwds
  def handle_info(%Message{name: :new_event, data: %{event: event}}, state) do
    {state, changed?} = Projects.register_cwd(state, event.cwd)

    if changed? do
      state = refresh_tasks(state)
      broadcast(state)
      {:noreply, state}
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
    {state, projects_changed?} = Projects.refresh_discovered_projects(state)

    old_tasks = state.tasks
    state = refresh_tasks(state)

    if state.tasks != old_tasks || projects_changed? do
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
    Health.run(state, Projects.active_project_path(state))
  end

  # ═══════════════════════════════════════════════════════
  # Project discovery (delegated to SwarmMonitor.Discovery)
  # ═══════════════════════════════════════════════════════

  defp scan_archives, do: Discovery.scan_archives()

  defp broadcast(state) do
    StateBus.broadcast(state)
  end
end
