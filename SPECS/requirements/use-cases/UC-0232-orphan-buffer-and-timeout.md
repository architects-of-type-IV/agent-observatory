---
id: UC-0232
title: Buffer an Orphaned Node and Attach It When Its Parent Arrives
status: draft
parent_fr: FR-8.3
adrs: [ADR-017]
---

# UC-0232: Buffer an Orphaned Node and Attach It When Its Parent Arrives

## Intent
When a node references a `parent_step_id` that is not yet present in ETS, `CausalDAG` must park the node in an in-memory orphan buffer keyed by `{session_id, parent_step_id}`. If the parent arrives within 30 seconds the node is retroactively attached and promoted to ETS. If the parent never arrives, the orphan is attached to the session's first root node with an `:orphan` warning flag so it is not lost. In both outcomes a DAG delta broadcast is emitted exactly once.

## Primary Actor
CausalDAG

## Supporting Actors
- In-memory orphan buffer (keyed by `{session_id, parent_step_id}`)
- ETS table keyed by `{session_id, trace_id}`
- DAG delta broadcast (PubSub topic `"session:dag:{session_id}"`)
- 30-second resolution timer (per buffer entry)

## Preconditions
- `CausalDAG` GenServer is running.
- The session has at least one root node in ETS (required for fallback attachment).
- The arriving orphan node is valid (all required fields present).

## Trigger
`CausalDAG.insert/2` is called with a Node whose `parent_step_id` is non-nil and whose parent `trace_id` is not found in the session's ETS table.

## Main Success Flow
1. `CausalDAG.insert/2` looks up `parent_step_id` in ETS and does not find it.
2. The node is placed in the orphan buffer under key `{session_id, parent_step_id}` with a UTC insertion timestamp.
3. A 30-second resolution timer is started for the buffer entry.
4. No ETS write and no broadcast occur at this point.
5. Within 30 seconds, the parent node arrives and is inserted into ETS via a separate `insert/2` call.
6. `CausalDAG` detects the parent's insertion, finds buffered children for this parent, and:
   a. Writes each buffered node to ETS.
   b. Updates the parent's `children` list to include the newly-attached child `trace_id`.
   c. Removes the buffer entry.
7. A delta broadcast is emitted with the attached child in `added_nodes`, the parent in `updated_nodes`, and the edge `{from: parent.trace_id, to: child.trace_id}` in `added_edges`.

## Alternate Flows
### A1: Multiple orphans share the same missing parent
Condition: Two or more nodes arrive with the same missing `parent_step_id`.
Steps:
1. Both are buffered under the same key.
2. When the parent arrives, all buffered children are promoted together.
3. A single delta broadcast includes all promoted children.

## Failure Flows
### F1: Parent does not arrive within 30 seconds
Condition: The 30-second timer fires without the parent having been inserted.
Steps:
1. `CausalDAG` retrieves the orphaned node from the buffer.
2. The node's struct has `orphan: true` added as a warning flag.
3. The node is attached to the session's first root node: the root's `children` list is updated to include the orphan's `trace_id`.
4. The node is written to ETS.
5. The buffer entry is cleared.
6. A delta broadcast is emitted with the orphan in `added_nodes` (with `orphan: true`), the root in `updated_nodes`, and the fallback edge in `added_edges`.
Result: The orphan is visible in the DAG and accessible via `get_session_dag/1`, flagged for operator review.

## Gherkin Scenarios

### S1: Parent arrives within 30 seconds — orphan promoted
```gherkin
Scenario: Orphaned node is attached when its parent arrives within 30 seconds
  Given session "sess-abc" has root node with trace_id "root-1"
  And node "child-B" arrives with parent_step_id "parent-A" which is not in ETS
  And "child-B" is placed in the orphan buffer with a UTC timestamp
  When node "parent-A" is inserted into ETS 8 seconds later
  Then "child-B" is removed from the orphan buffer and written to ETS
  And "parent-A" children list contains "child-B"
  And a dag_delta broadcast is emitted with "child-B" in added_nodes and "parent-A" in updated_nodes
```

### S2: Parent never arrives — orphan attached to root after 30 seconds
```gherkin
Scenario: Orphaned node is attached to session root after 30-second timeout
  Given session "sess-abc" has root node with trace_id "root-1"
  And node "stray-B" is placed in the orphan buffer at time T
  When 31 seconds elapse without the parent arriving
  Then "stray-B" is written to ETS with orphan flag set to true
  And "root-1" children list contains "stray-B"
  And the orphan buffer entry for "stray-B" is cleared
  And a dag_delta broadcast is emitted with "stray-B" in added_nodes
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that inserts a child node before its parent, then inserts the parent within 30 seconds, and asserts the child is correctly attached with an updated `children` list on the parent and a delta broadcast emitted.
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that inserts a child node, waits for the 30-second timer to fire (using fast-forward or mock timer), and asserts the orphan is attached to the session root with `orphan: true` and the buffer entry is removed.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Node struct with non-nil `parent_step_id` referencing a missing parent.
**Outputs:** Deferred `:ok`; DAG delta broadcast on attachment.
**State changes:** Orphan buffer entry created on arrival; removed on resolution. ETS entries for child and updated parent written on resolution.

## Traceability
- Parent FR: FR-8.3
- ADR: [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
