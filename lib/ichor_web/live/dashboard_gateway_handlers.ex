defmodule IchorWeb.DashboardGatewayHandlers do
  @moduledoc """
  PubSub subscription and handle_info handlers for Gateway data.

  Subscribes to gateway topics and routes live data into Phase 5 assigns
  (fleet_command, session_cluster, registry, scheduler, forensic, god_mode).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Ichor.Gateway.{CapabilityMap, CronScheduler, HeartbeatManager, WebhookRouter}
  alias Ichor.Mesh.CausalDAG

  @throughput_window_seconds 60
  @max_dlq_entries 200

  # ── Subscriptions ──────────────────────────────────────────────────

  @doc "Subscribe to all gateway PubSub topics. Call from mount/3 when connected."
  def subscribe_gateway_topics do
    # All gateway signals now flow through Signal categories (subscribed in mount).
    # This function is kept as a no-op for the import contract.
    :ok
  end

  @doc "Seed initial gateway data from GenServer queries. Call from mount/3."
  def seed_gateway_assigns(socket) do
    agents = safe_call(fn -> CapabilityMap.list_agents() end, %{})
    agent_types = derive_agent_types(agents)
    agent_classes = derive_agent_classes(agents)
    heartbeat_agents = safe_call(fn -> HeartbeatManager.list_agents() end, %{})
    zombie_agents = derive_zombie_list(safe_call(fn -> HeartbeatManager.list_zombies() end, %{}))
    cron_jobs = safe_call(fn -> CronScheduler.list_all_jobs() end, [])
    dlq_entries = safe_call(fn -> WebhookRouter.list_all_dead_letters() end, [])

    socket
    |> assign(:agent_types, agent_types)
    |> assign(:agent_classes, agent_classes)
    |> assign(:zombie_agents, zombie_agents)
    |> assign(:cron_jobs, cron_jobs)
    |> assign(:dlq_entries, dlq_entries)
    |> assign(:gateway_agents_raw, agents)
    |> assign(:heartbeat_agents, heartbeat_agents)
    |> assign(:throughput_events, [])
    |> assign(:entropy_scores, %{})
  end

  # ── handle_info clauses ────────────────────────────────────────────

  @doc """
  Routes a gateway PubSub message into socket assigns.

  Handles: decision_log, schema_violation, node_state_update, dead_letter,
  capability_update, entropy alerts, entropy state changes, and topology refreshes.
  """
  def handle_gateway_info(msg, socket)

  # DecisionLog -> throughput, cost, scratchpad, latency
  def handle_gateway_info(%Ichor.Signal.Payload{name: :decision_log, data: %{log: log}}, socket) do
    now = System.monotonic_time(:second)

    events = [{now, log} | socket.assigns[:throughput_events] || []]
    cutoff = now - @throughput_window_seconds
    events = Enum.filter(events, fn {t, _} -> t > cutoff end)
    throughput_rate = length(events) / @throughput_window_seconds

    cost_heatmap = update_cost_heatmap(socket.assigns.cost_heatmap, log)
    cost_attribution = update_cost_attribution(socket.assigns.cost_attribution, log)

    scratchpad_intents =
      maybe_append_intent(
        socket.assigns.scratchpad_intents,
        log,
        socket.assigns[:selected_session_id]
      )

    latency_metrics = update_latency_metrics(socket.assigns.latency_metrics, log)

    socket
    |> assign(:throughput_events, events)
    |> assign(:throughput_rate, Float.round(throughput_rate, 2))
    |> assign(:cost_heatmap, cost_heatmap)
    |> assign(:cost_attribution, cost_attribution)
    |> assign(:scratchpad_intents, scratchpad_intents)
    |> assign(:latency_metrics, latency_metrics)
  end

  # Schema violations are already captured via :new_event
  def handle_gateway_info(%Ichor.Signal.Payload{name: :schema_violation}, socket), do: socket

  def handle_gateway_info(%Ichor.Signal.Payload{name: :node_state_update, data: data}, socket) do
    node_status =
      Map.merge(socket.assigns[:node_status] || %{}, %{
        agent_id: data[:agent_id],
        state: data[:state]
      })

    assign(socket, :node_status, node_status)
  end

  def handle_gateway_info(
        %Ichor.Signal.Payload{name: :dead_letter, data: %{delivery: delivery}},
        socket
      ) do
    entries = [delivery | socket.assigns.dlq_entries] |> Enum.take(@max_dlq_entries)
    assign(socket, :dlq_entries, entries)
  end

  def handle_gateway_info(
        %Ichor.Signal.Payload{name: :capability_update, data: %{state_map: agents}},
        socket
      ) do
    socket
    |> assign(:gateway_agents_raw, agents)
    |> assign(:agent_types, derive_agent_types(agents))
    |> assign(:agent_classes, derive_agent_classes(agents))
  end

  def handle_gateway_info(%Ichor.Signal.Payload{name: :topology_snapshot, data: data}, socket) do
    push_event(socket, "fleet_topology_update", %{nodes: data.nodes, edges: data.edges})
  end

  def handle_gateway_info(%Ichor.Signal.Payload{name: :dag_delta, data: data}, socket) do
    if socket.assigns[:selected_session_id] == data[:session_id] do
      push_session_dag(socket, data[:session_id])
    else
      socket
    end
  end

  def handle_gateway_info(%Ichor.Signal.Payload{name: :entropy_alert, data: data}, socket) do
    scores =
      Map.put(
        socket.assigns[:entropy_scores] || %{},
        data[:session_id],
        data[:entropy_score]
      )

    assign(socket, :entropy_scores, scores)
  end

  # Catch-all
  def handle_gateway_info(_msg, socket), do: socket

  # ── Private helpers ────────────────────────────────────────────────

  defp safe_call(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end

  defp derive_agent_types(agents) when is_map(agents) do
    agents
    |> Enum.map(fn {agent_id, info} ->
      %{
        agent_id: agent_id,
        agent_type: get_in(info, [:capabilities, "type"]) || "unknown",
        capabilities: info[:capabilities] || %{},
        cluster_id: info[:cluster_id],
        registered_at: info[:registered_at]
      }
    end)
  end

  defp derive_agent_classes(agents) when is_map(agents) do
    agents
    |> Enum.group_by(fn {_id, info} ->
      get_in(info, [:capabilities, "class"]) || "default"
    end)
    |> Enum.map(fn {class, members} ->
      %{class: class, count: length(members), agent_ids: Enum.map(members, &elem(&1, 0))}
    end)
  end

  defp derive_zombie_list(zombies) when is_map(zombies) do
    Enum.map(zombies, fn {agent_id, info} ->
      %{agent_id: agent_id, last_seen: info[:last_seen], cluster_id: info[:cluster_id]}
    end)
  end

  defp update_cost_heatmap(existing, log) do
    case extract_cost(log) do
      nil -> existing
      entry -> [entry | existing] |> Enum.take(500)
    end
  end

  defp update_cost_attribution(existing, log) do
    case extract_cost(log) do
      nil -> existing
      entry -> [entry | existing] |> Enum.take(500)
    end
  end

  defp extract_cost(%{
         state_delta: %{cumulative_session_cost: cost},
         identity: %{agent_id: aid},
         meta: %{trace_id: sid}
       })
       when is_number(cost) do
    %{agent_id: aid, session_id: sid, cost: cost, timestamp: DateTime.utc_now()}
  end

  defp extract_cost(_), do: nil

  defp maybe_append_intent(intents, log, selected_session_id) do
    session_id = log.meta && log.meta.trace_id
    intent = log.cognition && log.cognition.intent

    if intent && session_id == selected_session_id && selected_session_id != nil do
      entry = build_intent_entry(intent, log.cognition)
      [entry | intents] |> Enum.take(100)
    else
      intents
    end
  end

  defp build_intent_entry(intent, cognition) do
    %{
      intent: intent,
      confidence: cognition && cognition.confidence_score,
      strategy: cognition && cognition.strategy_used,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Subscribe to a session's causal DAG topic and push the current DAG state to the JS hook.
  Unsubscribes from the previously selected session if any.
  """
  def subscribe_session_dag(socket, new_session_id) do
    old_session_id = socket.assigns[:selected_session_id]

    if old_session_id && old_session_id != new_session_id do
      Phoenix.PubSub.unsubscribe(Ichor.PubSub, "session:dag:#{old_session_id}")
    end

    if new_session_id do
      Phoenix.PubSub.subscribe(Ichor.PubSub, "session:dag:#{new_session_id}")
      push_session_dag(socket, new_session_id)
    else
      push_event(socket, "session_dag_update", %{nodes: [], edges: []})
    end
  end

  defp push_session_dag(socket, session_id) do
    case safe_call(fn -> CausalDAG.get_session_dag(session_id) end, {:error, :unavailable}) do
      {:ok, node_map} ->
        {nodes, edges} = dag_to_topology(node_map)
        push_event(socket, "session_dag_update", %{nodes: nodes, edges: edges})

      _ ->
        push_event(socket, "session_dag_update", %{nodes: [], edges: []})
    end
  end

  defp dag_to_topology(node_map) when is_map(node_map) do
    nodes =
      Enum.map(node_map, fn {_trace_id, node} ->
        %{
          trace_id: node.trace_id,
          agent_id: node.agent_id,
          state: map_action_state(node.action_status),
          x: nil,
          y: nil
        }
      end)

    edges =
      Enum.flat_map(node_map, fn {_trace_id, node} ->
        Enum.map(node.children, fn child_id ->
          %{
            from: node.trace_id,
            to: child_id,
            traffic_volume: 0,
            latency_ms: 0,
            status: "active",
            from_x: nil,
            from_y: nil,
            to_x: nil,
            to_y: nil
          }
        end)
      end)

    {nodes, edges}
  end

  defp map_action_state(:success), do: "active"
  defp map_action_state(:pending), do: "idle"
  defp map_action_state(:failure), do: "alert_entropy"
  defp map_action_state(:skipped), do: "blocked"
  defp map_action_state(s) when is_binary(s), do: s
  defp map_action_state(_), do: "idle"

  defp update_latency_metrics(metrics, log) do
    timestamp = if log.meta, do: log.meta.timestamp, else: nil

    case timestamp do
      %DateTime{} ->
        now = DateTime.utc_now()
        latency_ms = DateTime.diff(now, timestamp, :millisecond)

        samples = Map.get(metrics, :samples, [])
        samples = [latency_ms | samples] |> Enum.take(100)
        sorted = Enum.sort(samples)
        len = length(sorted)

        if len > 0 do
          %{
            samples: samples,
            p50: Enum.at(sorted, div(len, 2)),
            p95: Enum.at(sorted, trunc(len * 0.95)),
            p99: Enum.at(sorted, trunc(len * 0.99)),
            count: len
          }
        else
          metrics
        end

      _ ->
        metrics
    end
  end
end
