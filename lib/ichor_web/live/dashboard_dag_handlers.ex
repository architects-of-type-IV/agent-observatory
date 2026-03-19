defmodule IchorWeb.DashboardDagHandlers do
  @moduledoc """
  Event handlers for the DAG pipeline views.

  This is the DAG-facing pipeline handler surface for the dashboard.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ichor.Control.RuntimeQuery
  alias Ichor.Projects.{Runtime, Status}

  def dispatch("select_dag_project", p, s), do: handle_select_project(p, s)
  def dispatch("heal_dag_task", p, s), do: handle_heal_task(p, s)
  def dispatch("heal_task", p, s), do: handle_heal_task(p, s)
  def dispatch("reset_dag_stale", p, s), do: handle_reset_all_stale(p, s)
  def dispatch("run_dag_health_check", p, s), do: handle_run_health_check(p, s)
  def dispatch("reassign_dag_task", p, s), do: handle_reassign_dag_task(p, s)
  def dispatch("claim_dag_task", p, s), do: handle_claim_dag_task(p, s)
  def dispatch("trigger_dag_gc", p, s), do: handle_trigger_gc(p, s)
  def dispatch("select_dag_node", p, s), do: handle_select_dag_node(p, s)
  def dispatch("select_command_agent", p, s), do: handle_select_command_agent(p, s)
  def dispatch("send_command_message", p, s), do: handle_send_command_message(p, s)
  def dispatch("clear_command_selection", p, s), do: handle_clear_command_selection(p, s)

  def handle_select_project(%{"project" => key}, socket) do
    Status.set_active_project(key)
    socket
  end

  def handle_add_project(%{"path" => path}, socket) do
    key = Path.basename(path)
    Status.add_project(key, path)
    socket
  end

  def handle_heal_task(%{"id" => task_id}, socket) do
    Runtime.heal_task(task_id)
    socket
  end

  def handle_reassign_dag_task(%{"id" => task_id, "owner" => owner}, socket) do
    Runtime.reassign_task(task_id, owner)
    socket
  end

  def handle_reset_all_stale(_params, socket) do
    Runtime.reset_all_stale(10)
    socket
  end

  def handle_trigger_gc(%{"team" => team_name}, socket) do
    Runtime.trigger_gc(team_name)
    socket
  end

  def handle_run_health_check(_params, socket) do
    Runtime.run_health_check()
    socket
  end

  def handle_claim_dag_task(%{"id" => task_id, "agent" => agent}, socket) do
    Runtime.claim_task(task_id, agent)
    socket
  end

  def handle_select_dag_node(%{"id" => task_id}, socket) do
    dag = Status.state()
    task = Enum.find(dag.tasks, &(&1.id == task_id))

    current = socket.assigns[:selected_dag_task]
    selected = if current && current.id == task_id, do: nil, else: task

    socket
    |> assign(:selected_dag_task, selected)
  end

  def handle_select_command_agent(%{"id" => id}, socket) do
    current = socket.assigns[:selected_command_agent]

    if current && (current[:agent_id] == id || current[:name] == id) do
      assign(socket, :selected_command_agent, nil)
    else
      selected = RuntimeQuery.find_agent_entry(id, socket.assigns.teams, socket.assigns.events)
      assign(socket, :selected_command_agent, selected)
    end
  end

  def handle_clear_command_selection(_params, socket) do
    socket
    |> assign(:selected_command_agent, nil)
    |> assign(:selected_dag_task, nil)
  end

  def handle_send_command_message(%{"to" => to, "content" => content}, socket) do
    if content != "" do
      case Ichor.MessageRouter.send(%{from: "operator", to: to, content: content}) do
        {:ok, %{delivered: delivered}} when delivered > 0 ->
          Phoenix.LiveView.push_event(socket, "toast", %{
            message:
              "Sent to #{String.slice(to, 0, 12)} (#{delivered} channel#{if delivered > 1, do: "s", else: ""})",
            type: "success"
          })

        {:ok, %{delivered: 0}} ->
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
