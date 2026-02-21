defmodule ObservatoryWeb.DashboardSwarmHandlers do
  @moduledoc """
  Event handlers for the Swarm Control Center (Command, Pipeline, Protocols views).
  Handles project selection, task healing, reassignment, DAG node selection, etc.
  """
  import Phoenix.Component, only: [assign: 3]

  def handle_select_project(%{"project" => key}, socket) do
    Observatory.SwarmMonitor.set_active_project(key)
    socket
  end

  def handle_add_project(%{"path" => path}, socket) do
    key = Path.basename(path)
    Observatory.SwarmMonitor.add_project(key, path)
    socket
  end

  def handle_heal_task(%{"id" => task_id}, socket) do
    Observatory.SwarmMonitor.heal_task(task_id)
    socket
  end

  def handle_reassign_swarm_task(%{"id" => task_id, "owner" => owner}, socket) do
    Observatory.SwarmMonitor.reassign_task(task_id, owner)
    socket
  end

  def handle_reset_all_stale(_params, socket) do
    Observatory.SwarmMonitor.reset_all_stale()
    socket
  end

  def handle_trigger_gc(%{"team" => team_name}, socket) do
    Observatory.SwarmMonitor.trigger_gc(team_name)
    socket
  end

  def handle_run_health_check(_params, socket) do
    Observatory.SwarmMonitor.run_health_check()
    socket
  end

  def handle_claim_swarm_task(%{"id" => task_id, "agent" => agent}, socket) do
    Observatory.SwarmMonitor.claim_task(task_id, agent)
    socket
  end

  def handle_select_dag_node(%{"id" => task_id}, socket) do
    swarm = Observatory.SwarmMonitor.get_state()
    task = Enum.find(swarm.tasks, &(&1.id == task_id))

    current = socket.assigns[:selected_dag_task]
    selected = if current && current.id == task_id, do: nil, else: task

    socket
    |> assign(:selected_dag_task, selected)
    |> assign(:selected_command_task, selected)
  end

  def handle_select_command_agent(%{"id" => id}, socket) do
    current = socket.assigns[:selected_command_agent]

    if current && (current[:agent_id] == id || current[:name] == id) do
      socket
      |> assign(:selected_command_agent, nil)
      |> assign(:selected_command_task, nil)
    else
      # Search team members first, then build from events
      team_agent =
        socket.assigns.teams
        |> Enum.flat_map(& &1.members)
        |> Enum.find(fn m -> m[:agent_id] == id || m[:name] == id end)

      selected =
        team_agent ||
          %{
            agent_id: id,
            name: find_session_name(socket.assigns.events, id),
            session_id: id
          }

      # Find the agent's current task from swarm state
      swarm = socket.assigns[:swarm_state] || %{tasks: []}
      agent_name = selected[:name]

      task =
        if agent_name do
          Enum.find(swarm.tasks, fn t -> t.status == "in_progress" && t.owner == agent_name end)
        end

      socket
      |> assign(:selected_command_agent, selected)
      |> assign(:selected_command_task, task)
    end
  end

  defp find_session_name(events, session_id) do
    events
    |> Enum.find(fn e -> e.session_id == session_id end)
    |> case do
      nil -> String.slice(session_id, 0, 8)
      event -> if event.cwd, do: Path.basename(event.cwd), else: String.slice(session_id, 0, 8)
    end
  end

  def handle_clear_command_selection(_params, socket) do
    socket
    |> assign(:selected_command_agent, nil)
    |> assign(:selected_command_task, nil)
    |> assign(:selected_dag_task, nil)
  end

  def handle_send_command_message(%{"to" => to, "content" => content}, socket) do
    if content != "" do
      Observatory.Mailbox.send_message(to, "dashboard", content)
    end

    socket
  end
end
