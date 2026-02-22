defmodule ObservatoryWeb.DashboardGatewayHandlers do
  @moduledoc """
  PubSub subscription and handle_info handlers for Gateway data.

  Subscribes to gateway topics and routes live data into Phase 5 assigns
  (fleet_command, session_cluster, registry, scheduler, forensic, god_mode).
  """

  import Phoenix.Component, only: [assign: 3]

  alias Observatory.Gateway.{CapabilityMap, CronScheduler, HeartbeatManager, WebhookRouter}

  @throughput_window_seconds 60
  @max_dlq_entries 200

  # ── Subscriptions ──────────────────────────────────────────────────

  @doc "Subscribe to all gateway PubSub topics. Call from mount/3 when connected."
  def subscribe_gateway_topics do
    topics = [
      "gateway:messages",
      "gateway:violations",
      "gateway:topology",
      "gateway:entropy_alerts",
      "gateway:dlq",
      "gateway:capabilities"
    ]

    Enum.each(topics, &Phoenix.PubSub.subscribe(Observatory.PubSub, &1))
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

  # DecisionLog broadcast -> throughput, cost, scratchpad, latency
  def handle_gateway_info({:decision_log, log}, socket) do
    now = System.monotonic_time(:second)

    events = [{now, log} | socket.assigns[:throughput_events] || []]
    cutoff = now - @throughput_window_seconds
    events = Enum.filter(events, fn {t, _} -> t > cutoff end)
    throughput_rate = length(events) / @throughput_window_seconds

    cost_heatmap = update_cost_heatmap(socket.assigns.cost_heatmap, log)
    cost_attribution = update_cost_attribution(socket.assigns.cost_attribution, log)

    scratchpad_intents =
      maybe_append_intent(socket.assigns.scratchpad_intents, log, socket.assigns[:selected_session_id])

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
  def handle_gateway_info({:schema_violation, _event}, socket), do: socket

  # Topology node state update
  def handle_gateway_info({:node_state_update, data}, socket) do
    node_status = Map.merge(socket.assigns[:node_status] || %{}, %{
      agent_id: data.agent_id,
      state: data.state,
      timestamp: data[:timestamp]
    })

    assign(socket, :node_status, node_status)
  end

  # Dead letter notification -> append to dlq_entries
  def handle_gateway_info({:dead_letter, delivery}, socket) do
    entries = [delivery | socket.assigns.dlq_entries] |> Enum.take(@max_dlq_entries)
    assign(socket, :dlq_entries, entries)
  end

  # Capability map update -> refresh agent_types and agent_classes
  def handle_gateway_info({:capability_update, agents}, socket) do
    socket
    |> assign(:gateway_agents_raw, agents)
    |> assign(:agent_types, derive_agent_types(agents))
    |> assign(:agent_classes, derive_agent_classes(agents))
  end

  # Full topology refresh (nodes + edges from TopologyBuilder)
  def handle_gateway_info(%{nodes: _nodes, edges: _edges}, socket), do: socket

  # Entropy alert -> update per-session entropy scores
  def handle_gateway_info(%{event_type: "entropy_alert"} = alert, socket) do
    scores = Map.put(
      socket.assigns[:entropy_scores] || %{},
      alert.session_id,
      alert.entropy_score
    )

    assign(socket, :entropy_scores, scores)
  end

  # Entropy state change -> update node status
  def handle_gateway_info(%{session_id: session_id, state: state}, socket)
      when is_binary(session_id) and is_binary(state) do
    node_status = Map.merge(socket.assigns[:node_status] || %{}, %{
      session_id: session_id,
      state: state
    })

    assign(socket, :node_status, node_status)
  end

  # Catch-all
  def handle_gateway_info(_msg, socket), do: socket

  # ── Private helpers ────────────────────────────────────────────────

  defp safe_call(fun, default) do
    try do
      fun.()
    rescue
      _ -> default
    catch
      :exit, _ -> default
    end
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

  defp extract_cost(%{state_delta: %{cumulative_session_cost: cost}, identity: %{agent_id: aid}, meta: %{trace_id: sid}})
       when is_number(cost) do
    %{agent_id: aid, session_id: sid, cost: cost, timestamp: DateTime.utc_now()}
  end

  defp extract_cost(_), do: nil

  defp maybe_append_intent(intents, log, selected_session_id) do
    session_id = if log.meta, do: log.meta.trace_id, else: nil
    intent = if log.cognition, do: log.cognition.intent, else: nil

    if intent && session_id && session_id == selected_session_id do
      entry = %{
        intent: intent,
        confidence: (log.cognition && log.cognition.confidence_score) || nil,
        strategy: (log.cognition && log.cognition.strategy_used) || nil,
        timestamp: DateTime.utc_now()
      }

      [entry | intents] |> Enum.take(100)
    else
      intents
    end
  end

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
