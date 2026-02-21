---
id: UC-0235
title: Retrieve the Full Session DAG as an Adjacency Map
status: draft
parent_fr: FR-8.6
adrs: [ADR-017]
---

# UC-0235: Retrieve the Full Session DAG as an Adjacency Map

## Intent
`CausalDAG.get_session_dag/1` is the primary read API for the Session Drill-down view and for `TopologyBuilder`. It must return a complete adjacency map of every node currently in ETS for the given session, with `children` lists reflecting all attachments made up to the moment of the call. For unknown or already-pruned sessions, it must return a structured error rather than raising.

## Primary Actor
CausalDAG

## Supporting Actors
- ETS table keyed by `{session_id, trace_id}`
- TopologyBuilder (consumer)
- Session Drill-down LiveView (consumer)

## Preconditions
- `CausalDAG` GenServer is running.
- The session either has an active ETS table or has been pruned.

## Trigger
A caller invokes `CausalDAG.get_session_dag(session_id)`.

## Main Success Flow
1. Caller passes a valid `session_id` string.
2. `CausalDAG` locates the ETS table for that session.
3. All entries in the table are read and assembled into a map of the form `%{trace_id => %Node{}}`.
4. Each node's `children` list reflects all attachments made at the time of the call.
5. `CausalDAG` returns `{:ok, %{"trace-1" => %Node{...}, ...}}`.

## Alternate Flows
### A1: Session has zero nodes (empty but existing table)
Condition: The ETS table exists but no nodes have been inserted yet.
Steps:
1. `CausalDAG` reads the table and finds no entries.
2. Returns `{:ok, %{}}`.

## Failure Flows
### F1: Session not found
Condition: The given `session_id` has no corresponding ETS table (unknown session or already pruned).
Steps:
1. `CausalDAG` finds no ETS table for the given `session_id`.
2. Returns `{:error, :session_not_found}`.
Result: Caller receives a structured error; no exception is raised.

## Gherkin Scenarios

### S1: Known session with nodes returns full adjacency map
```gherkin
Scenario: get_session_dag returns all nodes for a known session
  Given session "sess-abc" has 12 nodes inserted into its ETS table
  When CausalDAG.get_session_dag/1 is called with "sess-abc"
  Then the function returns {:ok, map} where map contains exactly 12 entries
  And each entry key is a trace_id string
  And each entry value is a %Node{} struct with a populated children list
```

### S2: Unknown session returns structured error
```gherkin
Scenario: get_session_dag returns session_not_found for unknown session_id
  Given no ETS table exists for session_id "sess-unknown"
  When CausalDAG.get_session_dag/1 is called with "sess-unknown"
  Then the function returns {:error, :session_not_found}
  And no exception is raised
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that inserts 12 nodes for a session and calls `get_session_dag/1`, asserting the returned map contains all 12 trace_ids with correct `children` lists.
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that calls `get_session_dag/1` with an unknown `session_id` and asserts `{:error, :session_not_found}` is returned.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `session_id` (string).
**Outputs:** `{:ok, %{trace_id => %Node{}}}` or `{:error, :session_not_found}`.
**State changes:** None — read-only operation.

## Traceability
- Parent FR: FR-8.6
- ADR: [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
