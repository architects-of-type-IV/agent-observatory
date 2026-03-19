defmodule IchorWeb.DashboardPhase5Handlers do
  @moduledoc """
  Phase 5 event handlers: Fleet Command, Session Cluster, Registry,
  Scheduler, Forensic, and God Mode inline handlers.
  """

  import Phoenix.Component, only: [assign: 3]

  def dispatch("toggle_agent_grid", _p, s), do: handle_toggle_agent_grid(s)
  def dispatch("toggle_entropy_filter", _p, s), do: handle_toggle_entropy_filter(s)
  def dispatch("select_session", %{"session_id" => sid}, s), do: handle_select_session(sid, s)
  def dispatch("toggle_subpanel", %{"panel" => p}, s), do: handle_toggle_subpanel(p, s)

  def dispatch("sort_capability_directory", %{"field" => f}, s),
    do: handle_sort_capability_directory(f, s)

  def dispatch("update_route_weight", %{"agent_type" => at, "weight" => w}, s),
    do: handle_update_route_weight(at, w, s)

  def dispatch("retry_dlq_entry", %{"entry_id" => eid}, s), do: handle_retry_dlq_entry(eid, s)
  def dispatch("search_archive", %{"q" => q}, s), do: handle_search_archive(q, s)
  def dispatch("set_cost_group_by", %{"field" => f}, s), do: handle_set_cost_group_by(f, s)

  def dispatch("add_policy_rule", %{"name" => n, "condition" => c, "action" => a}, s),
    do: handle_add_policy_rule(n, c, a, s)

  def dispatch("toggle_forensic_panel", %{"panel" => p}, s),
    do: handle_toggle_forensic_panel(p, s)

  def dispatch("toggle_protocol_item", %{"id" => id}, s) do
    expanded = s.assigns.expanded_protocol_items

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    assign(s, :expanded_protocol_items, expanded)
  end

  def handle_toggle_agent_grid(socket) do
    assign(socket, :agent_grid_open, !socket.assigns.agent_grid_open)
  end

  # Session Cluster & Registry
  def handle_toggle_entropy_filter(socket) do
    assign(socket, :entropy_filter_active, !socket.assigns.entropy_filter_active)
  end

  def handle_select_session(sid, socket) do
    import IchorWeb.DashboardGatewayHandlers, only: [subscribe_session_dag: 2]
    socket = subscribe_session_dag(socket, sid)
    assign(socket, :selected_session_id, sid)
  end

  def handle_toggle_subpanel(panel, socket) do
    key = String.to_existing_atom("#{panel}_panel_open")
    assign(socket, key, !Map.get(socket.assigns, key, false))
  end

  def handle_sort_capability_directory(field, socket) do
    field_atom = String.to_existing_atom(field)

    new_dir =
      if socket.assigns.capability_sort_field == field_atom and
           socket.assigns.capability_sort_dir == :asc,
         do: :desc,
         else: :asc

    socket
    |> assign(:capability_sort_field, field_atom)
    |> assign(:capability_sort_dir, new_dir)
  end

  def handle_update_route_weight(agent_type, weight_str, socket) do
    case Integer.parse(weight_str) do
      {w, ""} when w >= 0 and w <= 100 ->
        weights = Map.put(socket.assigns.route_weights, agent_type, w)

        socket
        |> assign(:route_weights, weights)
        |> assign(
          :route_weight_errors,
          Map.delete(socket.assigns.route_weight_errors, agent_type)
        )

      _ ->
        errors = Map.put(socket.assigns.route_weight_errors, agent_type, "Must be 0-100")
        assign(socket, :route_weight_errors, errors)
    end
  end

  # Scheduler
  def handle_retry_dlq_entry(entry_id, socket) do
    dlq =
      Enum.map(socket.assigns.dlq_entries, fn entry ->
        if Map.get(entry, :id) == entry_id, do: Map.put(entry, :state, "pending"), else: entry
      end)

    assign(socket, :dlq_entries, dlq)
  end

  # Forensic
  def handle_search_archive(query, socket) do
    results =
      Enum.filter(socket.assigns.events, fn ev ->
        query != "" and String.contains?(String.downcase(inspect(ev)), String.downcase(query))
      end)

    socket
    |> assign(:archive_search, query)
    |> assign(:archive_results, results)
  end

  def handle_set_cost_group_by(field, socket) do
    assign(socket, :cost_group_by, String.to_existing_atom(field))
  end

  def handle_add_policy_rule(name, condition, action, socket) do
    rule = %{
      id: System.unique_integer([:positive]),
      name: name,
      condition: condition,
      action: action,
      enabled: true
    }

    assign(socket, :policy_rules, [rule | socket.assigns.policy_rules])
  end

  def handle_toggle_forensic_panel(panel, socket) do
    key = String.to_existing_atom("forensic_#{panel}_open")
    assign(socket, key, !Map.get(socket.assigns, key, false))
  end
end
