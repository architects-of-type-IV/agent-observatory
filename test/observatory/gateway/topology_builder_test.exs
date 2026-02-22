defmodule Observatory.Gateway.TopologyBuilderTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Observatory.Mesh.CausalDAG)
    start_supervised!(Observatory.Gateway.TopologyBuilder)
    :ok
  end

  describe "TopologyBuilder broadcasts to gateway:topology after DAG delta" do
    test "3-node chain produces correct topology" do
      session_id = "sess-test-#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      # Insert a 3-node chain
      root = %Observatory.Mesh.CausalDAG.Node{
        trace_id: "node-1",
        parent_step_id: nil,
        agent_id: "agent-a",
        intent: "search",
        confidence_score: 0.9,
        entropy_score: 0.5,
        action_status: :active,
        timestamp: System.monotonic_time()
      }

      child1 = %Observatory.Mesh.CausalDAG.Node{
        trace_id: "node-2",
        parent_step_id: "node-1",
        agent_id: "agent-a",
        intent: "list",
        confidence_score: 0.85,
        entropy_score: 0.4,
        action_status: :active,
        timestamp: System.monotonic_time()
      }

      child2 = %Observatory.Mesh.CausalDAG.Node{
        trace_id: "node-3",
        parent_step_id: "node-2",
        agent_id: "agent-a",
        intent: "read",
        confidence_score: 0.8,
        entropy_score: 0.3,
        action_status: :idle,
        timestamp: System.monotonic_time()
      }

      Observatory.Mesh.CausalDAG.insert(session_id, root)
      Observatory.Mesh.CausalDAG.insert(session_id, child1)
      Observatory.Mesh.CausalDAG.insert(session_id, child2)

      # Collect broadcasts until we have the complete topology
      {nodes, edges} = collect_broadcasts_until(fn n -> length(n) == 3 end, nil, nil, 0)

      assert length(nodes) == 3
      assert length(edges) == 2

      # Verify node structure
      assert Enum.all?(nodes, fn n -> n.trace_id && n.agent_id && n.state end)

      # Verify edge structure
      assert Enum.all?(edges, fn e -> e.from && e.to && e.status end)
    end
  end

  # Helper to collect broadcasts until a condition is met
  defp collect_broadcasts_until(_condition, _nodes, _edges, attempts) when attempts >= 10 do
    {[], []}
  end

  defp collect_broadcasts_until(condition, _nodes, _edges, attempts) do
    receive do
      %{nodes: nodes, edges: edges} ->
        if condition.(nodes) do
          {nodes, edges}
        else
          collect_broadcasts_until(condition, nodes, edges, attempts + 1)
        end
    after
      100 ->
        collect_broadcasts_until(condition, nil, nil, attempts + 1)
    end
  end

  describe "TopologyBuilder skips pruned session silently" do
    test "handles session_not_found without crashing" do
      session_id = "sess-nonexistent-#{System.unique_integer()}"

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      # Manually send a dag_delta for a session that doesn't exist
      send(
        Process.whereis(Observatory.Gateway.TopologyBuilder),
        %{event: "dag_delta", session_id: session_id}
      )

      # Wait a bit
      Process.sleep(50)

      # Assert no broadcast was received
      refute_receive %{nodes: _, edges: _}, 200
    end
  end

  describe "gateway:topology PubSub topic contract" do
    test "broadcast on gateway:topology delivers to subscribers" do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      # Broadcast a test message directly
      test_payload = %{
        nodes: [
          %{trace_id: "test-1", agent_id: "agent-1", state: :active, x: nil, y: nil}
        ],
        edges: [
          %{from: "test-1", to: "test-2", status: "active"}
        ]
      }

      Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:topology", test_payload)

      # Assert the subscriber receives it
      assert_receive ^test_payload
    end
  end
end
