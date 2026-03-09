defmodule IchorWeb.DashboardSelectionHandlers do
  @moduledoc """
  Handles entity selection and deselection events.
  Each dispatch/3 clause returns the updated socket (caller wraps in {:noreply, ...}).
  """

  import Phoenix.Component, only: [assign: 3]

  def dispatch("select_event", %{"id" => id}, socket) do
    cur = socket.assigns.selected_event
    sel = if cur && cur.id == id, do: nil, else: Enum.find(socket.assigns.events, &(&1.id == id))
    socket |> clear_selections() |> assign(:selected_event, sel)
  end

  def dispatch("select_task", %{"id" => id}, socket) do
    cur = socket.assigns.selected_task
    sel = if cur && cur[:id] == id, do: nil, else: Enum.find(socket.assigns.active_tasks, &(&1[:id] == id))
    socket |> clear_selections() |> assign(:selected_task, sel)
  end

  def dispatch("select_agent", %{"id" => id}, socket) do
    cur = socket.assigns.selected_agent
    sel = if cur && cur[:agent_id] == id, do: nil, else: find_agent(socket.assigns.teams, id)
    socket |> clear_selections() |> assign(:selected_agent, sel)
  end

  def dispatch("select_team", %{"name" => name}, socket) do
    sel = if socket.assigns.selected_team == name, do: nil, else: name
    assign(socket, :selected_team, sel)
  end

  def dispatch("close_detail", _params, socket), do: assign(socket, :selected_event, nil)
  def dispatch("close_task_detail", _params, socket), do: assign(socket, :selected_task, nil)

  defp clear_selections(socket) do
    socket
    |> assign(:selected_event, nil)
    |> assign(:selected_task, nil)
    |> assign(:selected_agent, nil)
  end

  defp find_agent(teams, agent_id) do
    teams |> Enum.flat_map(& &1.members) |> Enum.find(&(&1[:agent_id] == agent_id))
  end
end
