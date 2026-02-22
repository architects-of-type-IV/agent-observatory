---
id: UC-0233
title: Reject a Node Insertion That Would Create a Cycle
status: draft
parent_fr: FR-8.4
adrs: [ADR-017]
---

# UC-0233: Reject a Node Insertion That Would Create a Cycle

## Intent
The Causal DAG must remain acyclic at all times. Before writing any non-root node to ETS, `CausalDAG` walks the ancestor chain of the declared `parent_step_id` upward. If the incoming `trace_id` appears anywhere in that chain, the insertion is aborted and `{:error, :cycle_detected}` is returned. This protects the DAG invariant without requiring a full graph traversal on every insert — only the ancestor path needs to be checked.

## Primary Actor
CausalDAG

## Supporting Actors
- ETS table keyed by `{session_id, trace_id}` (read-only during ancestor walk)
- DAG delta broadcast (PubSub topic `"session:dag:{session_id}"`)

## Preconditions
- `CausalDAG` GenServer is running.
- The session ETS table contains at least one root node and a partial ancestor chain against which the cycle check can run.
- The incoming node is non-root (its `parent_step_id` is non-nil).

## Trigger
`CausalDAG.insert/2` is called with a Node whose `parent_step_id` would, if accepted, introduce a cycle (i.e., the incoming `trace_id` already exists as an ancestor of the declared parent).

## Main Success Flow
1. `CausalDAG.insert/2` receives a non-root Node with a non-nil `parent_step_id`.
2. `CausalDAG` walks the ancestor chain: it reads the parent node from ETS, then the parent's parent, and so on until it reaches a root (nil `parent_step_id`) or an ETS miss.
3. The incoming `trace_id` is not found anywhere in the ancestor chain.
4. No cycle is detected; the node is inserted normally.
5. A delta broadcast is emitted; `:ok` is returned.

## Alternate Flows
None defined for this UC — the linear success path is the only non-failure outcome.

## Failure Flows
### F1: Cycle detected in ancestor chain
Condition: The incoming node's `trace_id` matches a `trace_id` encountered while walking the ancestor chain of the declared `parent_step_id`.
Steps:
1. `CausalDAG` encounters the incoming `trace_id` during the ancestor walk.
2. `CausalDAG` aborts the insertion immediately without writing to ETS.
3. No delta broadcast is emitted.
4. `CausalDAG.insert/2` returns `{:error, :cycle_detected}`.
Result: The DAG remains acyclic; the cycle-inducing node is discarded.

## Gherkin Scenarios

### S1: Ancestor chain is clean — node inserted normally
```gherkin
Scenario: Node with clean ancestor chain is accepted
  Given session "sess-dag" has root node A with trace_id "node-a"
  And node B with trace_id "node-b" and parent_step_id "node-a" is already in ETS
  And node C with trace_id "node-c" and parent_step_id "node-b" is being inserted
  When CausalDAG.insert/2 is called with "sess-dag" and node C
  Then the ancestor walk finds node-b then node-a then nil with no match for "node-c"
  And node C is written to ETS
  And CausalDAG.insert/2 returns :ok
```

### S2: Cycle detected — insertion rejected
```gherkin
Scenario: Cycle-inducing node is rejected
  Given session "sess-dag" has root node A with trace_id "node-a"
  And node B with trace_id "node-b" and parent_step_id "node-a" is in ETS
  And node C with trace_id "node-c" and parent_step_id "node-b" is in ETS
  And an incoming node has trace_id "node-a" and parent_step_id "node-c"
  When CausalDAG.insert/2 is called with this cycle-inducing node
  Then the ancestor walk finds node-c then node-b then node-a and matches "node-a"
  And no entry is written to ETS
  And CausalDAG.insert/2 returns {:error, :cycle_detected}
  And no dag_delta broadcast is emitted
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that attempts to insert a node whose `trace_id` already appears in its own ancestor chain and asserts `{:error, :cycle_detected}` is returned with no ETS modification.
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that inserts a chain of nodes A -> B -> C where no `trace_id` repeats and asserts the final insertion returns `:ok` and the node is present in ETS.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Non-root Node struct with `parent_step_id` that leads to a cycle.
**Outputs:** `{:error, :cycle_detected}` with no ETS write and no PubSub broadcast.
**State changes:** None on cycle detection.

## Traceability
- Parent FR: FR-8.4
- ADR: [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
