defmodule IchorWeb.DashboardSwarmHandlers do
  @moduledoc """
  Event handlers for the Swarm Control Center (Command, Pipeline, Protocols views).
  Handles project selection, task healing, reassignment, DAG node selection, etc.
  """
  import Phoenix.Component, only: [assign: 3]

  alias Ichor.Fleet.Overseer
  alias Ichor.Fleet.RuntimeQuery

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
    Overseer.set_active_project(key)
    socket
  end

  def handle_add_project(%{"path" => path}, socket) do
    key = Path.basename(path)
    Overseer.add_project(key, path)
    socket
  end

  def handle_heal_task(%{"id" => task_id}, socket) do
    Overseer.heal_task(task_id)
    socket
  end

  def handle_reassign_swarm_task(%{"id" => task_id, "owner" => owner}, socket) do
    Overseer.reassign_task(task_id, owner)
    socket
  end

  def handle_reset_all_stale(_params, socket) do
    Overseer.reset_all_stale()
    socket
  end

  def handle_trigger_gc(%{"team" => team_name}, socket) do
    Overseer.trigger_gc(team_name)
    socket
  end

  def handle_run_health_check(_params, socket) do
    Overseer.run_health_check()
    socket
  end

  def handle_claim_swarm_task(%{"id" => task_id, "agent" => agent}, socket) do
    Overseer.claim_task(task_id, agent)
    socket
  end

  def handle_select_dag_node(%{"id" => task_id}, socket) do
    swarm = Overseer.get_state()
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
      selected = RuntimeQuery.find_agent_entry(id, socket.assigns.teams, socket.assigns.events)

      task =
        RuntimeQuery.find_active_task(
          selected[:name],
          socket.assigns[:swarm_state] || %{tasks: []}
        )

      socket
      |> assign(:selected_command_agent, selected)
      |> assign(:selected_command_task, task)
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
      end
    else
      socket
    end
  end
end
