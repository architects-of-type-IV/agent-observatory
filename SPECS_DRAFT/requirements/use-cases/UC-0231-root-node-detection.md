---
id: UC-0231
title: Detect and Insert a Root Node in the Causal DAG
status: draft
parent_fr: FR-8.2
adrs: [ADR-017]
---

# UC-0231: Detect and Insert a Root Node in the Causal DAG

## Intent
A DecisionLog step that carries no causal predecessor (`parent_step_id: nil`) must be treated as a session root and inserted directly into ETS without consulting the orphan buffer. A session may accumulate multiple independent roots, and `CausalDAG` must never coerce a second root into the subtree of the first.

## Primary Actor
CausalDAG

## Supporting Actors
- ETS table keyed by `{session_id, trace_id}`
- DAG delta broadcast (PubSub topic `"session:dag:{session_id}"`)

## Preconditions
- `CausalDAG` GenServer is running.
- The Node struct is otherwise valid (all required fields present).

## Trigger
`CausalDAG.insert/2` is called with a Node whose `parent_step_id` is `nil`.

## Main Success Flow
1. `CausalDAG.insert/2` receives a Node with `parent_step_id: nil`.
2. `CausalDAG` identifies the node as a root and bypasses orphan-buffer logic entirely.
3. The node is written to ETS with `children: []`.
4. A delta broadcast is emitted to `"session:dag:{session_id}"` with the new root in `added_nodes`.
5. `:ok` is returned.

## Alternate Flows
### A1: Second root arrives for the same session
Condition: The session's ETS table already contains at least one root node.
Steps:
1. The second node with `parent_step_id: nil` arrives.
2. `CausalDAG` inserts it as an additional independent root — it is NOT attached to the existing root's subtree.
3. Delta broadcast includes the second root in `added_nodes`.
4. Both roots are independently queryable via `get_session_dag/1`.

## Failure Flows
### F1: Root node with missing required fields
Condition: A node with `parent_step_id: nil` is submitted but lacks one of the other eight required fields.
Steps:
1. `CausalDAG` applies the same field-presence check regardless of root status.
2. Returns `{:error, :missing_fields}`; nothing is written to ETS.
Result: No root is recorded; no broadcast is emitted.

## Gherkin Scenarios

### S1: First root node inserted successfully
```gherkin
Scenario: Node with nil parent_step_id is inserted as a session root
  Given no nodes exist for session_id "sess-root-test"
  And a Node struct is prepared with parent_step_id set to nil and children set to []
  When CausalDAG.insert/2 is called with "sess-root-test" and the Node struct
  Then the node is stored in ETS with children: []
  And a dag_delta broadcast is emitted to "session:dag:sess-root-test" with the node in added_nodes
```

### S2: Second root is accepted without coercion into first root's subtree
```gherkin
Scenario: A second root node is inserted independently
  Given session_id "sess-root-test" already has root node with trace_id "root-1"
  And a new Node struct is prepared with parent_step_id nil and trace_id "root-2"
  When CausalDAG.insert/2 is called with "sess-root-test" and the new Node struct
  Then ETS contains both "root-1" and "root-2" as independent roots
  And "root-1" children list does not contain "root-2"
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that inserts a root node (parent_step_id nil) and asserts it is stored with `children: []` and appears in the `added_nodes` of the delta broadcast.
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that inserts two nodes both with `parent_step_id: nil` for the same session and asserts both are retrievable as independent roots with no parent-child relationship between them.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `session_id` (string), Node struct with `parent_step_id: nil`.
**Outputs:** `:ok`; PubSub broadcast to `"session:dag:{session_id}"`.
**State changes:** ETS entry created for the root node with `children: []`.

## Traceability
- Parent FR: FR-8.2
- ADR: [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
