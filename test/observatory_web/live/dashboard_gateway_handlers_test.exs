defmodule ObservatoryWeb.DashboardGatewayHandlersTest do
  use ExUnit.Case, async: false

  alias Observatory.Gateway.{CapabilityMap, HeartbeatManager}
  alias Observatory.Mesh.DecisionLog

  import ObservatoryWeb.DashboardGatewayHandlers

  defp build_socket(assigns \\ %{}) do
    defaults = %{
      throughput_events: [],
      throughput_rate: nil,
      cost_heatmap: [],
      cost_attribution: [],
      scratchpad_intents: [],
      latency_metrics: %{},
      node_status: nil,
      dlq_entries: [],
      entropy_scores: %{},
      gateway_agents_raw: %{},
      agent_types: [],
      agent_classes: [],
      selected_session_id: nil
    }

    merged = Map.merge(defaults, assigns)
    %Phoenix.LiveView.Socket{assigns: Map.merge(%{__changed__: %{}}, merged)}
  end

  defp build_decision_log(overrides \\ %{}) do
    base = %DecisionLog{
      meta: %DecisionLog.Meta{
        trace_id: "session-abc",
        timestamp: DateTime.utc_now()
      },
      identity: %DecisionLog.Identity{
        agent_id: "agent-1",
        agent_type: "researcher",
        capability_version: "1.0.0"
      },
      cognition: %DecisionLog.Cognition{
        intent: "search_docs",
        confidence_score: 0.85,
        strategy_used: "depth_first",
        entropy_score: 0.9
      },
      action: %DecisionLog.Action{
        status: :success,
        tool_call: "grep",
        tool_input: "pattern"
      },
      state_delta: %DecisionLog.StateDelta{
        cumulative_session_cost: 0.042,
        tokens_consumed: 1500
      },
      control: nil
    }

    Map.merge(base, overrides)
  end

  describe "handle_gateway_info/2 - decision_log" do
    test "updates throughput_rate from decision_log messages" do
      socket = build_socket()
      log = build_decision_log()

      result = handle_gateway_info({:decision_log, log}, socket)
      assert result.assigns.throughput_rate != nil
      assert is_float(result.assigns.throughput_rate)
      assert length(result.assigns.throughput_events) == 1
    end

    test "accumulates cost_heatmap from logs with cost data" do
      socket = build_socket()
      log = build_decision_log()

      result = handle_gateway_info({:decision_log, log}, socket)
      assert length(result.assigns.cost_heatmap) == 1
      [entry] = result.assigns.cost_heatmap
      assert entry.agent_id == "agent-1"
      assert entry.cost == 0.042
    end

    test "accumulates cost_attribution from logs with cost data" do
      socket = build_socket()
      log = build_decision_log()

      result = handle_gateway_info({:decision_log, log}, socket)
      assert length(result.assigns.cost_attribution) == 1
    end

    test "appends scratchpad intents when selected session matches" do
      socket = build_socket(%{selected_session_id: "session-abc"})
      log = build_decision_log()

      result = handle_gateway_info({:decision_log, log}, socket)
      assert length(result.assigns.scratchpad_intents) == 1
      [intent] = result.assigns.scratchpad_intents
      assert intent.intent == "search_docs"
      assert intent.confidence == 0.85
    end

    test "does not append scratchpad intents when session does not match" do
      socket = build_socket(%{selected_session_id: "other-session"})
      log = build_decision_log()

      result = handle_gateway_info({:decision_log, log}, socket)
      assert result.assigns.scratchpad_intents == []
    end

    test "computes latency metrics from decision_log timestamps" do
      socket = build_socket()
      log = build_decision_log()

      result = handle_gateway_info({:decision_log, log}, socket)
      metrics = result.assigns.latency_metrics
      assert Map.has_key?(metrics, :p50)
      assert Map.has_key?(metrics, :p95)
      assert Map.has_key?(metrics, :count)
      assert metrics.count == 1
    end

    test "skips cost data when state_delta is nil" do
      socket = build_socket()
      log = build_decision_log(%{state_delta: nil})

      result = handle_gateway_info({:decision_log, log}, socket)
      assert result.assigns.cost_heatmap == []
    end
  end

  describe "handle_gateway_info/2 - schema_violation" do
    test "passes through without assign changes" do
      socket = build_socket()
      event = %{"event_type" => "schema_violation", "agent_id" => "a-1"}
      result = handle_gateway_info({:schema_violation, event}, socket)
      assert result == socket
    end
  end

  describe "handle_gateway_info/2 - node_state_update" do
    test "updates node_status assign" do
      socket = build_socket()

      data = %{agent_id: "agent-1", state: :schema_violation, timestamp: "2026-02-22T00:00:00Z"}
      result = handle_gateway_info({:node_state_update, data}, socket)
      assert result.assigns.node_status.agent_id == "agent-1"
      assert result.assigns.node_status.state == :schema_violation
    end
  end

  describe "handle_gateway_info/2 - dead_letter" do
    test "appends delivery to dlq_entries" do
      socket = build_socket(%{dlq_entries: [%{id: "old"}]})
      delivery = %{id: "new-dlq", agent_id: "a-1", target_url: "http://example.com"}

      result = handle_gateway_info({:dead_letter, delivery}, socket)
      assert length(result.assigns.dlq_entries) == 2
      assert hd(result.assigns.dlq_entries).id == "new-dlq"
    end
  end

  describe "handle_gateway_info/2 - entropy_alert" do
    test "updates entropy_scores for the session" do
      socket = build_socket()

      alert = %{
        event_type: "entropy_alert",
        session_id: "session-xyz",
        entropy_score: 0.2,
        agent_id: "agent-1",
        window_size: 5,
        repeated_pattern: %{intent: "search", tool_call: "grep", action_status: "success"},
        occurrence_count: 4
      }

      result = handle_gateway_info(alert, socket)
      assert result.assigns.entropy_scores["session-xyz"] == 0.2
    end
  end

  describe "handle_gateway_info/2 - capability_update" do
    test "refreshes agent_types and agent_classes" do
      socket = build_socket()

      agents = %{
        "agent-1" => %{capabilities: %{"type" => "researcher", "class" => "primary"}, cluster_id: "c1", registered_at: DateTime.utc_now()},
        "agent-2" => %{capabilities: %{"type" => "builder", "class" => "primary"}, cluster_id: "c1", registered_at: DateTime.utc_now()}
      }

      result = handle_gateway_info({:capability_update, agents}, socket)
      assert length(result.assigns.agent_types) == 2
      assert length(result.assigns.agent_classes) == 1
      assert hd(result.assigns.agent_classes).class == "primary"
      assert hd(result.assigns.agent_classes).count == 2
    end
  end

  describe "handle_gateway_info/2 - entropy state change" do
    test "updates node_status with session state" do
      socket = build_socket()

      msg = %{session_id: "sess-1", state: "alert_entropy"}
      result = handle_gateway_info(msg, socket)
      assert result.assigns.node_status.session_id == "sess-1"
      assert result.assigns.node_status.state == "alert_entropy"
    end
  end

  describe "handle_gateway_info/2 - catch_all" do
    test "returns socket unchanged for unknown messages" do
      socket = build_socket()
      result = handle_gateway_info(:unknown_message, socket)
      assert result == socket
    end
  end

  describe "seed_gateway_assigns/1" do
    test "populates agent_types from CapabilityMap" do
      # Register an agent so list_agents returns data
      CapabilityMap.register_agent("test-agent", %{"type" => "worker", "class" => "default"}, "c1")

      socket = build_socket()
      result = seed_gateway_assigns(socket)

      assert is_list(result.assigns.agent_types)
      assert Enum.any?(result.assigns.agent_types, fn t -> t.agent_id == "test-agent" end)

      # Clean up
      CapabilityMap.remove_agent("test-agent")
    end

    test "populates zombie_agents from HeartbeatManager" do
      socket = build_socket()
      result = seed_gateway_assigns(socket)
      assert is_list(result.assigns.zombie_agents)
    end

    test "initializes throughput_events as empty list" do
      socket = build_socket()
      result = seed_gateway_assigns(socket)
      assert result.assigns.throughput_events == []
    end

    test "initializes entropy_scores as empty map" do
      socket = build_socket()
      result = seed_gateway_assigns(socket)
      assert result.assigns.entropy_scores == %{}
    end
  end

  describe "HeartbeatManager query APIs" do
    setup do
      pid = Process.whereis(HeartbeatManager)
      :sys.replace_state(pid, fn _state -> %{} end)
      :ok
    end

    test "list_agents returns all tracked agents" do
      HeartbeatManager.record_heartbeat("agent-1", "cluster-a")
      HeartbeatManager.record_heartbeat("agent-2", "cluster-b")

      agents = HeartbeatManager.list_agents()
      assert map_size(agents) == 2
      assert Map.has_key?(agents, "agent-1")
      assert Map.has_key?(agents, "agent-2")
    end

    test "list_zombies returns stale agents" do
      # Inject a stale entry
      stale_time = DateTime.add(DateTime.utc_now(), -100, :second)

      :sys.replace_state(Process.whereis(HeartbeatManager), fn _state ->
        %{"zombie-agent" => %{last_seen: stale_time, cluster_id: "cluster-z"}}
      end)

      zombies = HeartbeatManager.list_zombies()
      assert map_size(zombies) == 1
      assert Map.has_key?(zombies, "zombie-agent")
    end

    test "list_zombies returns empty when all agents are fresh" do
      HeartbeatManager.record_heartbeat("fresh-agent", "cluster-a")
      zombies = HeartbeatManager.list_zombies()
      assert zombies == %{}
    end
  end

  describe "CapabilityMap PubSub broadcast" do
    test "broadcasts on register_agent" do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:capabilities")
      CapabilityMap.register_agent("broadcast-test", %{"type" => "test"}, "c1")
      assert_receive {:capability_update, agents}
      assert Map.has_key?(agents, "broadcast-test")
      CapabilityMap.remove_agent("broadcast-test")
    end

    test "broadcasts on remove_agent" do
      CapabilityMap.register_agent("remove-test", %{"type" => "test"}, "c1")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:capabilities")
      CapabilityMap.remove_agent("remove-test")
      assert_receive {:capability_update, agents}
      refute Map.has_key?(agents, "remove-test")
    end
  end
end
