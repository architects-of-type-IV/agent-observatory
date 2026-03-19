defmodule Ichor.Dag.Runtime do
  @moduledoc """
  Live DAG pipeline runtime.

  This is the active GenServer behind project discovery, task refresh,
  health polling, and corrective task actions for `tasks.jsonl` pipelines.
  """
  use GenServer

  alias Ichor.Dag.Actions
  alias Ichor.Dag.Analysis
  alias Ichor.Dag.Discovery
  alias Ichor.Dag.HealthReport
  alias Ichor.Dag.Projects
  alias Ichor.Signals.Message

  @tasks_poll_interval 3_000
  @health_poll_interval 30_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def state, do: GenServer.call(__MODULE__, :get_state)

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

    Ichor.Signals.subscribe(:events)

    send(self(), :poll_tasks)
    Process.send_after(self(), :poll_health, 5_000)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call({:set_active_project, key}, _from, state) do
    case Projects.set_active_project(state, key) do
      {:ok, next_state} ->
        next_state = refresh_tasks(next_state)
        broadcast(next_state)
        {:reply, :ok, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:add_project, key, path}, _from, state) do
    case Projects.add_project(state, key, path) do
      {:ok, next_state} ->
        next_state = refresh_tasks(next_state)
        broadcast(next_state)
        {:reply, :ok, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:heal_task, task_id}, _from, state) do
    result = Actions.heal_task(state, task_id)
    next_state = refresh_tasks(state)
    broadcast(next_state)
    {:reply, result, next_state}
  end

  def handle_call({:reassign_task, task_id, new_owner}, _from, state) do
    result = Actions.reassign_task(state, task_id, new_owner)
    next_state = refresh_tasks(state)
    broadcast(next_state)
    {:reply, result, next_state}
  end

  def handle_call({:reset_all_stale, threshold_min}, _from, state) do
    result = Actions.reset_all_stale(state, threshold_min)
    next_state = refresh_tasks(state)
    broadcast(next_state)
    {:reply, result, next_state}
  end

  def handle_call({:trigger_gc, team_name}, _from, state) do
    result = Actions.trigger_gc(state, team_name)
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
    result = Actions.claim_task(state, task_id, agent_name)
    next_state = refresh_tasks(state)
    broadcast(next_state)
    {:reply, result, next_state}
  end

  def handle_info(%Message{name: :new_event, data: %{event: event}}, state) do
    {next_state, changed?} = Projects.register_cwd(state, event.cwd)

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

    {next_state, projects_changed?} = Projects.refresh_discovered_projects(state)
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

  defp refresh_tasks(state), do: Analysis.refresh_tasks(state)

  defp do_health_check(state) do
    HealthReport.run(state, Projects.active_project_path(state))
  end

  defp scan_archives, do: Discovery.scan_archives()

  defp broadcast(state), do: Ichor.Signals.emit(:dag_status, %{state_map: state})
end
