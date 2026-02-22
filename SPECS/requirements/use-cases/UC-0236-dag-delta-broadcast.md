---
id: UC-0236
title: Broadcast a DAG Delta After a Successful Node Insertion
status: draft
parent_fr: FR-8.7
adrs: [ADR-017]
---

# UC-0236: Broadcast a DAG Delta After a Successful Node Insertion

## Intent
Every successful node insertion or orphan attachment must produce exactly one PubSub broadcast on the `"session:dag:{session_id}"` topic. The broadcast payload carries the complete delta — newly added nodes, nodes with updated `children` lists, and newly created edges — so subscribers can update their views incrementally without re-fetching the full DAG. Rejected insertions (cycle or missing fields) and unresolved buffer placements must produce no broadcast.

## Primary Actor
CausalDAG

## Supporting Actors
- Phoenix PubSub (topic `"session:dag:{session_id}"`)
- Session Drill-down LiveView (subscriber)
- TopologyBuilder (subscriber)

## Preconditions
- `CausalDAG` GenServer is running.
- A Phoenix PubSub adapter is configured and operational.
- The session ETS table exists.

## Trigger
`CausalDAG.insert/2` successfully writes a node to ETS, or an orphan attachment is resolved.

## Main Success Flow
1. Node D is inserted as a child of C; `CausalDAG` writes the node to ETS.
2. `CausalDAG` updates C's `children` list in ETS to include D's `trace_id`.
3. `CausalDAG` broadcasts the following map to `"session:dag:sess-abc"`:
   ```
   %{
     event: "dag_delta",
     session_id: "sess-abc",
     added_nodes: [D],
     updated_nodes: [C],
     added_edges: [%{from: C.trace_id, to: D.trace_id}]
   }
   ```
4. Subscribers receive the broadcast synchronously.

## Alternate Flows
### A1: Root node inserted — no parent update needed
Condition: Inserted node is a root (no parent to update).
Steps:
1. Node is written to ETS.
2. Broadcast is emitted with the root in `added_nodes`, empty `updated_nodes`, and empty `added_edges`.

### A2: Orphan promoted from buffer
Condition: A parent's arrival triggers promotion of a buffered orphan.
Steps:
1. Orphan is written to ETS; parent's `children` list is updated.
2. Broadcast includes orphan in `added_nodes`, parent in `updated_nodes`, and the retroactive edge in `added_edges`.

## Failure Flows
### F1: Insertion rejected (cycle or missing fields)
Condition: `CausalDAG.insert/2` returns `{:error, :cycle_detected}` or `{:error, :missing_fields}`.
Steps:
1. No ETS write occurs.
2. No PubSub broadcast is emitted.
Result: The `"session:dag:{session_id}"` topic is unmodified; subscribers observe no change.

### F2: Node placed in orphan buffer (parent not yet present)
Condition: Node is buffered because its parent is missing.
Steps:
1. Node is placed in the orphan buffer; no ETS write occurs.
2. No broadcast is emitted until the orphan is resolved.
Result: Broadcast is deferred; subscribers see no partial update.

## Gherkin Scenarios

### S1: Child node inserted — delta broadcast emitted with edge
```gherkin
Scenario: Successful child insertion triggers a dag_delta broadcast
  Given session "sess-abc" has node C with trace_id "node-c" in ETS
  And node D with trace_id "node-d" and parent_step_id "node-c" is valid and complete
  When CausalDAG.insert/2 is called with "sess-abc" and node D
  Then a broadcast is published to "session:dag:sess-abc"
  And the broadcast payload has event "dag_delta"
  And added_nodes contains node D
  And updated_nodes contains node C with "node-d" in its children list
  And added_edges contains {from: "node-c", to: "node-d"}
```

### S2: Cycle-detected rejection — no broadcast emitted
```gherkin
Scenario: Rejected insertion due to cycle produces no broadcast
  Given session "sess-abc" has an existing ancestor chain
  And an incoming node would create a cycle
  When CausalDAG.insert/2 is called and returns {:error, :cycle_detected}
  Then no message is published to "session:dag:sess-abc"
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that inserts a valid child node and asserts a broadcast is received on `"session:dag:{session_id}"` with the correct `added_nodes`, `updated_nodes`, and `added_edges` keys populated.
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that triggers a cycle-detected rejection and asserts no broadcast is received on the topic.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Successful ETS write or orphan resolution.
**Outputs:** PubSub message on `"session:dag:{session_id}"` with keys `event`, `session_id`, `added_nodes`, `updated_nodes`, `added_edges`.
**State changes:** Subscribers' local state updated via the broadcast payload.

## Traceability
- Parent FR: FR-8.7
- ADR: [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
