defmodule Observatory.Mesh.CausalDAGTest do
  use ExUnit.Case, async: false

  alias Observatory.Mesh.CausalDAG
  alias Observatory.Mesh.CausalDAG.Node

  setup do
    pid = start_supervised!({CausalDAG, []})
    %{pid: pid}
  end

  defp build_node(overrides) do
    defaults = [
      trace_id: "trace-#{System.unique_integer([:positive])}",
      parent_step_id: nil,
      agent_id: "agent-1",
      intent: "explore",
      confidence_score: 0.9,
      entropy_score: 0.5,
      action_status: :success,
      timestamp: DateTime.utc_now()
    ]

    struct!(Node, Keyword.merge(defaults, overrides))
  end

  # 3.1.1.4 - Node Struct & ETS Table Setup

  describe "insert/2 with valid fields" do
    test "writes node to ETS and returns :ok" do
      node = build_node(trace_id: "node-valid", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-t1", node)

      {:ok, dag} = CausalDAG.get_session_dag("sess-t1")
      assert Map.has_key?(dag, "node-valid")
      assert dag["node-valid"].trace_id == "node-valid"
    end
  end

  describe "insert/2 with missing fields" do
    test "with missing agent_id returns {:error, :missing_fields}" do
      node = build_node(trace_id: "node-invalid", agent_id: nil)
      assert {:error, :missing_fields} = CausalDAG.insert("sess-t2", node)

      # Session table should not have been created
      assert {:error, :session_not_found} = CausalDAG.get_session_dag("sess-t2")
    end

    test "with missing intent returns {:error, :missing_fields}" do
      node = build_node(trace_id: "node-no-intent", intent: nil)
      assert {:error, :missing_fields} = CausalDAG.insert("sess-t3", node)
    end

    test "with missing confidence_score returns {:error, :missing_fields}" do
      node = build_node(trace_id: "node-no-conf", confidence_score: nil)
      assert {:error, :missing_fields} = CausalDAG.insert("sess-t4", node)
    end
  end

  # 3.1.2.4 - Orphan Buffer

  describe "orphan buffer" do
    test "orphan is promoted when its parent arrives within 30 seconds" do
      root = build_node(trace_id: "root-1", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-orphan", root)

      # Insert child whose parent doesn't exist yet -> buffered
      child = build_node(trace_id: "child-1", parent_step_id: "missing-parent")
      assert :ok = CausalDAG.insert("sess-orphan", child)

      # Child should be in buffer, not in DAG
      {:ok, dag_before} = CausalDAG.get_session_dag("sess-orphan")
      refute Map.has_key?(dag_before, "child-1")

      # Insert the missing parent
      parent = build_node(trace_id: "missing-parent", parent_step_id: "root-1")
      assert :ok = CausalDAG.insert("sess-orphan", parent)

      # Child should now be promoted
      {:ok, dag_after} = CausalDAG.get_session_dag("sess-orphan")
      assert Map.has_key?(dag_after, "child-1")
      assert "child-1" in dag_after["missing-parent"].children
    end

    test "orphan is attached to root with orphan: true after timeout", %{pid: pid} do
      root = build_node(trace_id: "root-1", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-timeout", root)

      orphan = build_node(trace_id: "orphan-1", parent_step_id: "never-arriving")
      assert :ok = CausalDAG.insert("sess-timeout", orphan)

      # Manipulate buffer: delete current entry and re-insert with stale timestamp
      :ets.delete(:causal_dag_orphan_buffer, {"sess-timeout", "never-arriving"})
      stale_time = System.monotonic_time(:millisecond) - 31_000

      :ets.insert(
        :causal_dag_orphan_buffer,
        {{"sess-timeout", "never-arriving"}, orphan, stale_time}
      )

      # Trigger orphan check; get_session_dag call acts as sync barrier
      send(pid, :check_orphans)

      {:ok, dag} = CausalDAG.get_session_dag("sess-timeout")
      assert Map.has_key?(dag, "orphan-1")
      assert dag["orphan-1"].orphan == true
    end
  end

  # 3.1.3.3 - Cycle Prevention

  describe "cycle prevention" do
    test "insert/2 detects cycle A->B->A and returns {:error, :cycle_detected}" do
      node_a = build_node(trace_id: "node-a", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-cycle", node_a)

      node_b = build_node(trace_id: "node-b", parent_step_id: "node-a")
      assert :ok = CausalDAG.insert("sess-cycle", node_b)

      # Try to insert node-a again as child of node-b -> cycle
      cycle_node = build_node(trace_id: "node-a", parent_step_id: "node-b")
      assert {:error, :cycle_detected} = CausalDAG.insert("sess-cycle", cycle_node)

      # ETS should still have only 2 nodes
      {:ok, dag} = CausalDAG.get_session_dag("sess-cycle")
      assert map_size(dag) == 2
    end

    test "insert/2 accepts a clean chain A->B->C without cycle error" do
      node_a = build_node(trace_id: "node-a", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-clean", node_a)

      node_b = build_node(trace_id: "node-b", parent_step_id: "node-a")
      assert :ok = CausalDAG.insert("sess-clean", node_b)

      node_c = build_node(trace_id: "node-c", parent_step_id: "node-b")
      assert :ok = CausalDAG.insert("sess-clean", node_c)

      {:ok, dag} = CausalDAG.get_session_dag("sess-clean")
      assert map_size(dag) == 3
    end
  end

  # 3.1.4.3 - Fork Nodes

  describe "fork nodes" do
    test "two children with same parent produce a fork node" do
      root = build_node(trace_id: "node-a", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-fork", root)

      child_x = build_node(trace_id: "node-x", parent_step_id: "node-a")
      assert :ok = CausalDAG.insert("sess-fork", child_x)

      child_y = build_node(trace_id: "node-y", parent_step_id: "node-a")
      assert :ok = CausalDAG.insert("sess-fork", child_y)

      {:ok, children} = CausalDAG.get_children("sess-fork", "node-a")
      assert "node-x" in children
      assert "node-y" in children
      assert length(children) == 2
    end

    test "single child returns a list of length 1" do
      root = build_node(trace_id: "node-a", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-single", root)

      child = build_node(trace_id: "node-b", parent_step_id: "node-a")
      assert :ok = CausalDAG.insert("sess-single", child)

      {:ok, children} = CausalDAG.get_children("sess-single", "node-a")
      assert children == ["node-b"]
    end
  end

  # Additional coverage: get_session_dag

  describe "get_session_dag/1" do
    test "returns {:error, :session_not_found} for unknown session" do
      assert {:error, :session_not_found} = CausalDAG.get_session_dag("sess-unknown")
    end
  end

  # Additional coverage: get_children

  describe "get_children/2" do
    test "returns {:error, :not_found} for unknown session" do
      assert {:error, :not_found} = CausalDAG.get_children("sess-unknown", "trace-1")
    end

    test "returns {:error, :not_found} for unknown trace_id" do
      root = build_node(trace_id: "root-1", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-gc", root)

      assert {:error, :not_found} = CausalDAG.get_children("sess-gc", "nonexistent")
    end
  end

  # 3.2.1.2 - get_session_dag/1 full session query

  describe "get_session_dag/1 with a full session" do
    test "returns all 12 nodes for a known session" do
      root = build_node(trace_id: "full-root", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-full", root)

      Enum.reduce(1..11, "full-root", fn i, parent_id ->
        trace_id = "full-node-#{i}"
        node = build_node(trace_id: trace_id, parent_step_id: parent_id)
        assert :ok = CausalDAG.insert("sess-full", node)
        trace_id
      end)

      {:ok, dag} = CausalDAG.get_session_dag("sess-full")
      assert map_size(dag) == 12

      Enum.each(dag, fn {_key, node} ->
        assert %Node{} = node
      end)
    end
  end

  # 3.2.2.2 - DAG Delta Broadcast

  describe "DAG delta broadcast" do
    test "successful child insertion broadcasts dag_delta on session:dag topic" do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "session:dag:sess-broadcast")

      root = build_node(trace_id: "broadcast-root", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-broadcast", root)

      child = build_node(trace_id: "broadcast-child", parent_step_id: "broadcast-root")
      assert :ok = CausalDAG.insert("sess-broadcast", child)

      assert_receive %{
        event: "dag_delta",
        added_nodes: [_],
        updated_nodes: [_],
        added_edges: [%{from: _, to: _}]
      }, 1000
    end

    test "cycle-detected rejection emits no broadcast" do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "session:dag:sess-cycle-broadcast")

      node_a = build_node(trace_id: "cb-node-a", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-cycle-broadcast", node_a)
      assert_receive %{event: "dag_delta"}, 500

      node_b = build_node(trace_id: "cb-node-b", parent_step_id: "cb-node-a")
      assert :ok = CausalDAG.insert("sess-cycle-broadcast", node_b)
      assert_receive %{event: "dag_delta"}, 500

      cycle_node = build_node(trace_id: "cb-node-a", parent_step_id: "cb-node-b")
      assert {:error, :cycle_detected} = CausalDAG.insert("sess-cycle-broadcast", cycle_node)

      refute_receive %{event: "dag_delta"}, 200
    end
  end

  # 3.2.3.3 - ETS Pruning on is_terminal

  describe "ETS pruning on is_terminal" do
    test "nodes remain queryable during 5-minute grace window" do
      root = build_node(trace_id: "prune-root", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-prune-grace", root)

      CausalDAG.signal_terminal("sess-prune-grace")

      assert {:ok, dag} = CausalDAG.get_session_dag("sess-prune-grace")
      assert Map.has_key?(dag, "prune-root")
    end

    test "prune_session message deletes ETS table and returns session_not_found", %{pid: pid} do
      root = build_node(trace_id: "prune-delete-root", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-prune-delete", root)

      assert {:ok, _} = CausalDAG.get_session_dag("sess-prune-delete")

      send(pid, {:prune_session, "sess-prune-delete"})

      assert {:error, :session_not_found} = CausalDAG.get_session_dag("sess-prune-delete")
    end

    test "duplicate terminal signal does not reset the deletion timer", %{pid: pid} do
      root = build_node(trace_id: "dup-signal-root", parent_step_id: nil)
      assert :ok = CausalDAG.insert("sess-dup-signal", root)

      CausalDAG.signal_terminal("sess-dup-signal")
      CausalDAG.signal_terminal("sess-dup-signal")

      state = :sys.get_state(pid)
      assert map_size(state.pending_deletions) == 1
      assert Map.has_key?(state.pending_deletions, "sess-dup-signal")
    end
  end
end
