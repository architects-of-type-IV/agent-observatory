---
id: UC-0241
title: TopologyBuilder Derives and Broadcasts Topology via gateway:topology
status: draft
parent_fr: FR-8.12
adrs: [ADR-016, ADR-017]
---

# UC-0241: TopologyBuilder Derives and Broadcasts Topology via gateway:topology

## Intent
`TopologyBuilder` must derive node and edge descriptors by reading exclusively from `CausalDAG.get_session_dag/1` and broadcast the result to the `"gateway:topology"` PubSub topic. The Fleet Command LiveView must subscribe to that topic during `mount/3` and forward each payload to the `TopologyMap` hook via `push_event/3`. Direct ETS reads from the LiveView are not permitted. When `TopologyBuilder` crashes and restarts, it must emit a full snapshot rather than an incremental delta to resynchronize subscribers.

## Primary Actor
TopologyBuilder

## Supporting Actors
- CausalDAG (data source via `get_session_dag/1`)
- Phoenix PubSub (topic `"gateway:topology"`)
- Fleet Command LiveView (subscriber, forwards to `TopologyMap` hook)

## Preconditions
- `CausalDAG` GenServer is running with at least one active session.
- Fleet Command LiveView is mounted and subscribed to `"gateway:topology"`.
- `TopologyBuilder` is running and subscribed to DAG delta events to know when to refresh.

## Trigger
`TopologyBuilder` receives a DAG delta broadcast on `"session:dag:{session_id}"` for any active session.

## Main Success Flow
1. `TopologyBuilder` receives a DAG delta event for session "sess-abc".
2. `TopologyBuilder` calls `CausalDAG.get_session_dag("sess-abc")` to obtain the full adjacency map.
3. `TopologyBuilder` derives a list of node descriptors from the adjacency map, each including `trace_id`, `agent_id`, `state`, and a position hint.
4. `TopologyBuilder` derives a list of edge descriptors from the `children` lists, each including `from`, `to`, `traffic_volume`, `latency_ms`, and `status`.
5. `TopologyBuilder` broadcasts `%{nodes: node_list, edges: edge_list}` to `"gateway:topology"`.
6. Fleet Command LiveView receives the broadcast and calls `push_event(socket, "topology_update", %{nodes: node_list, edges: edge_list})`.
7. The `TopologyMap` hook receives `topology_update` and schedules a canvas redraw.

## Alternate Flows
### A1: TopologyBuilder restarts after a crash
Condition: `TopologyBuilder` process restarts due to an unhandled error.
Steps:
1. On first successful `get_session_dag/1` call after restart, `TopologyBuilder` broadcasts a full snapshot for all active sessions.
2. Subscribers that received no broadcast during the crash interval resynchronize from the full snapshot.

## Failure Flows
### F1: CausalDAG returns session_not_found for a pruned session
Condition: `CausalDAG.get_session_dag/1` returns `{:error, :session_not_found}` because the session was pruned between the DAG delta event and the read.
Steps:
1. `TopologyBuilder` receives `{:error, :session_not_found}`.
2. `TopologyBuilder` skips that session silently.
3. No partial broadcast is emitted for the pruned session.
4. `TopologyBuilder` continues processing remaining active sessions.
Result: Other sessions are unaffected; the pruned session disappears naturally from the next topology broadcast.

## Gherkin Scenarios

### S1: TopologyBuilder derives and broadcasts topology from CausalDAG
```gherkin
Scenario: TopologyBuilder reads DAG and broadcasts node and edge lists
  Given session "sess-abc" has an active ETS table in CausalDAG with nodes and edges
  And Fleet Command LiveView is subscribed to "gateway:topology"
  When a DAG delta event triggers TopologyBuilder to read the session
  Then TopologyBuilder calls CausalDAG.get_session_dag("sess-abc")
  And TopologyBuilder broadcasts {nodes: [...], edges: [...]} to "gateway:topology"
  And Fleet Command LiveView receives the broadcast and calls push_event with "topology_update"
```

### S2: Pruned session is skipped without crashing TopologyBuilder
```gherkin
Scenario: TopologyBuilder skips a session that was pruned between delta and read
  Given a DAG delta event arrives for session "sess-pruned"
  And CausalDAG.get_session_dag("sess-pruned") returns {:error, :session_not_found}
  When TopologyBuilder processes the delta
  Then TopologyBuilder emits no broadcast for "sess-pruned"
  And TopologyBuilder does not crash
  And other active sessions continue to receive topology broadcasts normally
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/topology_builder_test.exs` passes a test that triggers a DAG delta, calls `TopologyBuilder` to read from `CausalDAG`, and asserts a `"gateway:topology"` broadcast is received containing `nodes` and `edges` keys.
- [ ] `mix test test/observatory/gateway/topology_builder_test.exs` passes a test where `CausalDAG.get_session_dag/1` returns `{:error, :session_not_found}` and asserts `TopologyBuilder` does not crash and emits no broadcast for that session.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** DAG delta event (trigger); `CausalDAG.get_session_dag/1` result (node adjacency map).
**Outputs:** PubSub broadcast on `"gateway:topology"` with `nodes` and `edges` lists.
**State changes:** Fleet Command LiveView socket updated with latest topology; `TopologyMap` hook canvas redrawn.

## Traceability
- Parent FR: FR-8.12, FR-8.13
- ADR: [ADR-016](../../decisions/ADR-016-canvas-topology-renderer.md), [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
