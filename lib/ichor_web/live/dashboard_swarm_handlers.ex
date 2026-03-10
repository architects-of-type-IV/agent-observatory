defmodule IchorWeb.DashboardSwarmHandlers do
  @moduledoc """
  Event handlers for the Swarm Control Center (Command, Pipeline, Protocols views).
  Handles project selection, task healing, reassignment, DAG node selection, etc.
  """
  import Phoenix.Component, only: [assign: 3]

  def dispatch("select_project", p, s), do: handle_select_project(p, s)
  def dispatch("heal_task", p, s), do: handle_heal_task(p, s)
  def dispatch("reset_all_stale", p, s), do: handle_reset_all_stale(p, s)
  def dispatch("run_health_check", p, s), do: handle_run_health_check(p, s)
  def dispatch("reassign_swarm_task", p, s), do: handle_reassign_swarm_task(p, s)
  def dispatch("claim_swarm_task", p, s), do: handle_claim_swarm_task(p, s)
  def dispatch("trigger_gc", p, s), do: handle_trigger_gc(p, s)
  def dispatch("select_dag_node", p, s), do: handle_select_dag_node(p, s)
  def dispatch("select_command_agent", p, s), do: handle_select_command_agent(p, s)
  def dispatch("send_command_message", p, s), do: handle_send_command_message(p, s)
  def dispatch("select_subagent", p, s), do: handle_select_subagent(p, s)
  def dispatch("clear_command_selection", p, s), do: handle_clear_command_selection(p, s)

  def handle_select_project(%{"project" => key}, socket) do
    Ichor.SwarmMonitor.set_active_project(key)
    socket
  end

  def handle_add_project(%{"path" => path}, socket) do
    key = Path.basename(path)
    Ichor.SwarmMonitor.add_project(key, path)
    socket
  end

  def handle_heal_task(%{"id" => task_id}, socket) do
    Ichor.SwarmMonitor.heal_task(task_id)
    socket
  end

  def handle_reassign_swarm_task(%{"id" => task_id, "owner" => owner}, socket) do
    Ichor.SwarmMonitor.reassign_task(task_id, owner)
    socket
  end

  def handle_reset_all_stale(_params, socket) do
    Ichor.SwarmMonitor.reset_all_stale()
    socket
  end

  def handle_trigger_gc(%{"team" => team_name}, socket) do
    Ichor.SwarmMonitor.trigger_gc(team_name)
    socket
  end

  def handle_run_health_check(_params, socket) do
    Ichor.SwarmMonitor.run_health_check()
    socket
  end

  def handle_claim_swarm_task(%{"id" => task_id, "agent" => agent}, socket) do
    Ichor.SwarmMonitor.claim_task(task_id, agent)
    socket
  end

  def handle_select_dag_node(%{"id" => task_id}, socket) do
    swarm = Ichor.SwarmMonitor.get_state()
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
      nil ->
        Ichor.Gateway.AgentRegistry.AgentEntry.short_id(session_id)

      event ->
        if event.tmux_session,
          do: event.tmux_session,
          else: Ichor.Gateway.AgentRegistry.AgentEntry.short_id(session_id)
    end
  end

  def handle_select_subagent(%{"parent_id" => parent_id, "tool_use_id" => tool_use_id}, socket) do
    agent_index = socket.assigns[:agent_index] || %{}
    parent = Map.get(agent_index, parent_id, %{})
    subs = parent[:subagents] || []

    case Enum.find(subs, &(&1[:tool_use_id] == tool_use_id)) do
      nil ->
        socket

      sub ->
        selected = %{
          agent_id: "sub:#{tool_use_id}",
          name: sub[:description] || sub[:type] || "subagent",
          session_id: parent_id,
          subagent: sub
        }

        socket
        |> assign(:selected_command_agent, selected)
        |> assign(:selected_command_task, nil)
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
      case Ichor.Operator.send(to, content) do
        {:ok, delivered} when delivered > 0 ->
          Phoenix.LiveView.push_event(socket, "toast", %{
            message:
              "Sent to #{String.slice(to, 0, 12)} (#{delivered} channel#{if delivered > 1, do: "s", else: ""})",
            type: "success"
          })

        {:ok, 0} ->
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "No delivery channel for #{String.slice(to, 0, 12)}",
            type: "warning"
          })

        {:error, _} ->
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Send failed",
            type: "error"
          })
      end
    else
      socket
    end
  end
end
