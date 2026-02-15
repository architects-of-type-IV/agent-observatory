defmodule ObservatoryWeb.DashboardTeamInspectorHandlers do
  @moduledoc """
  Event handlers for team inspector UI interactions.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  import ObservatoryWeb.DashboardTeamHelpers, only: [detect_role: 2, team_member_sids: 1]

  def handle_inspect_team(%{"team" => team_name}, socket) do
    inspected = socket.assigns.inspected_teams
    teams = socket.assigns.teams
    team = Enum.find(teams, fn t -> t[:name] == team_name end)

    if team && team_name not in Enum.map(inspected, & &1[:name]) do
      assign(socket, :inspected_teams, inspected ++ [team])
    else
      socket
    end
  end

  def handle_remove_from_inspector(%{"team" => team_name}, socket) do
    inspected = Enum.reject(socket.assigns.inspected_teams, fn t -> t[:name] == team_name end)
    assign(socket, :inspected_teams, inspected)
  end

  def handle_close_all_inspector(socket) do
    socket |> assign(:inspected_teams, []) |> assign(:inspector_size, :collapsed)
  end

  def handle_toggle_inspector_layout(socket) do
    new = if socket.assigns.inspector_layout == :horizontal, do: :vertical, else: :horizontal
    assign(socket, :inspector_layout, new)
  end

  def handle_toggle_maximize_inspector(socket) do
    assign(socket, :inspector_maximized, !socket.assigns.inspector_maximized)
  end

  def handle_set_inspector_size(%{"size" => size}, socket) do
    socket
    |> assign(:inspector_size, safe_size_atom(size))
    |> push_event("set_drawer_state", %{size: size})
  end

  def handle_set_output_mode(%{"mode" => mode}, socket) do
    assign(socket, :output_mode, safe_mode_atom(mode))
  end

  def handle_toggle_agent_output(%{"agent_id" => agent_id}, socket) do
    toggles = socket.assigns.agent_toggles
    current = Map.get(toggles, agent_id, true)
    assign(socket, :agent_toggles, Map.put(toggles, agent_id, !current))
  end

  def handle_set_message_target(%{"target" => target}, socket) do
    assign(socket, :selected_message_target, target)
  end

  def handle_send_targeted_message(%{"target" => target, "content" => content}, socket) do
    session_ids = resolve_message_targets(target, socket.assigns.teams)

    case session_ids do
      [] ->
        {:noreply,
         push_event(socket, "show_toast", %{message: "No targets found", type: "warning"})}

      sids ->
        Observatory.Mailbox.broadcast_to_many(sids, "dashboard", content)

        {:noreply,
         push_event(socket, "show_toast", %{
           message: "Sent to #{length(sids)} agent(s)",
           type: "success"
         })}
    end
  end

  # Private: resolve target string to list of session IDs

  defp resolve_message_targets("all_teams", teams) do
    teams |> Enum.flat_map(&team_member_sids/1) |> Enum.uniq()
  end

  defp resolve_message_targets("team:" <> team_name, teams) do
    case Enum.find(teams, fn t -> t[:name] == team_name end) do
      nil -> []
      team -> team_member_sids(team)
    end
  end

  defp resolve_message_targets("lead:" <> team_name, teams) do
    case Enum.find(teams, fn t -> t[:name] == team_name end) do
      nil ->
        []

      team ->
        team[:members]
        |> Enum.filter(fn m -> detect_role(team, m) == :lead end)
        |> Enum.map(& &1[:agent_id])
        |> Enum.reject(&is_nil/1)
    end
  end

  defp resolve_message_targets("member:" <> session_id, _teams), do: [session_id]
  defp resolve_message_targets(_, _teams), do: []

  defp safe_size_atom("collapsed"), do: :collapsed
  defp safe_size_atom("default"), do: :default
  defp safe_size_atom("maximized"), do: :maximized
  defp safe_size_atom(_), do: :default

  defp safe_mode_atom("all_live"), do: :all_live
  defp safe_mode_atom("leads_only"), do: :leads_only
  defp safe_mode_atom("all_agents"), do: :all_agents
  defp safe_mode_atom(_), do: :all_live
end
