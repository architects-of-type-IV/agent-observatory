defmodule IchorWeb.DashboardPipelineHandlers do
  @moduledoc """
  Event handlers for the pipeline board views.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ichor.Factory.Runtime
  alias Ichor.Signals.Bus
  alias Ichor.Workshop.Agent, as: ControlAgent
  alias IchorWeb.Presentation

  def dispatch("select_pipeline_project", p, s), do: handle_select_project(p, s)
  def dispatch("heal_pipeline_task", p, s), do: handle_heal_task(p, s)
  def dispatch("heal_task", p, s), do: handle_heal_task(p, s)
  def dispatch("reset_pipeline_stale", p, s), do: handle_reset_all_stale(p, s)
  def dispatch("run_pipeline_health_check", p, s), do: handle_run_health_check(p, s)
  def dispatch("reassign_pipeline_task", p, s), do: handle_reassign_pipeline_task(p, s)
  def dispatch("claim_pipeline_task", p, s), do: handle_claim_pipeline_task(p, s)
  def dispatch("trigger_pipeline_gc", p, s), do: handle_trigger_gc(p, s)
  def dispatch("select_pipeline_task", p, s), do: handle_select_pipeline_task(p, s)
  def dispatch("select_command_agent", p, s), do: handle_select_command_agent(p, s)
  def dispatch("send_command_message", p, s), do: handle_send_command_message(p, s)
  def dispatch("clear_command_selection", p, s), do: handle_clear_command_selection(p, s)

  def handle_select_project(%{"project" => key}, socket) do
    Runtime.set_active_project(key)
    socket
  end

  def handle_add_project(%{"path" => path}, socket) do
    key = Path.basename(path)
    Runtime.add_project(key, path)
    socket
  end

  def handle_heal_task(%{"id" => task_id}, socket) do
    Runtime.heal_task(task_id)
    socket
  end

  def handle_reassign_pipeline_task(%{"id" => task_id, "owner" => owner}, socket) do
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

  def handle_claim_pipeline_task(%{"id" => task_id, "agent" => agent}, socket) do
    Runtime.claim_task(task_id, agent)
    socket
  end

  def handle_select_pipeline_task(%{"id" => task_id}, socket) do
    pipeline_state = Runtime.state()
    task = Enum.find(pipeline_state.tasks, &(&1.id == task_id))

    current = socket.assigns[:selected_pipeline_task]
    selected = if current && current.id == task_id, do: nil, else: task

    socket
    |> assign(:selected_pipeline_task, selected)
  end

  def handle_select_command_agent(%{"id" => id}, socket) do
    current = socket.assigns[:selected_command_agent]

    if current && (current[:agent_id] == id || current[:name] == id) do
      assign(socket, :selected_command_agent, nil)
    else
      selected = find_agent_entry(id, socket.assigns.teams, socket.assigns.events)
      assign(socket, :selected_command_agent, selected)
    end
  end

  def handle_clear_command_selection(_params, socket) do
    socket
    |> assign(:selected_command_agent, nil)
    |> assign(:selected_pipeline_task, nil)
  end

  def handle_send_command_message(%{"to" => to, "content" => content}, socket) do
    if content != "" do
      case Bus.send(%{
             from: "operator",
             to: to,
             content: content,
             transport: :operator
           }) do
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

  defp find_agent_entry(id, teams, events) do
    team_agent =
      teams
      |> Enum.flat_map(& &1.members)
      |> Enum.find(fn member -> member[:agent_id] == id || member[:name] == id end)

    team_agent || %{agent_id: id, name: find_session_name(events, id), session_id: id}
  end

  defp find_session_name(events, session_id) do
    case Enum.find(events, &(&1.session_id == session_id)) do
      nil -> fallback_session_name(session_id)
      event -> event.tmux_session || fallback_session_name(session_id)
    end
  end

  defp fallback_session_name(session_id) do
    case find_agent_by_id(session_id) do
      nil ->
        Presentation.short_id(session_id)

      agent ->
        agent[:name] || agent["name"] || agent.session_id || agent.agent_id ||
          Presentation.short_id(session_id)
    end
  end

  defp find_agent_by_id(query) when is_binary(query) do
    ControlAgent.all!()
    |> Enum.find(fn agent ->
      agent.agent_id == query or agent.session_id == query or
        agent.short_name == query or agent.name == query
    end)
  end
end
