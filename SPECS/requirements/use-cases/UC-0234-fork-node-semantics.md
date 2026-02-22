---
id: UC-0234
title: Derive and Render Fork Nodes from Multi-Child DAG Nodes
status: draft
parent_fr: FR-8.5
adrs: [ADR-017]
---

# UC-0234: Derive and Render Fork Nodes from Multi-Child DAG Nodes

## Intent
A node becomes a fork when two or more children declare it as their `parent_step_id`. Fork status is not a stored flag — it is derived at read time from the length of the node's `children` list. `CausalDAG` must update `children` atomically on each child attachment, and `TopologyBuilder` must emit N outgoing edges for a fork, one per child, so the topology canvas renders a 1-to-N visual fan-out.

## Primary Actor
CausalDAG

## Supporting Actors
- TopologyBuilder (reads fork nodes via `CausalDAG.get_session_dag/1`)
- TopologyMap JS hook (renders the resulting edges on canvas)
- ETS table keyed by `{session_id, trace_id}`

## Preconditions
- `CausalDAG` GenServer is running.
- At least one parent node exists in ETS for the session.

## Trigger
A second (or subsequent) child node is inserted with a `parent_step_id` pointing to an existing ETS node, causing that parent's `children` list to grow beyond length 1.

## Main Success Flow
1. Child node X is inserted with `parent_step_id` = "node-A"; "node-A" `children` list is updated to include X's `trace_id`.
2. Child node Y is inserted with `parent_step_id` = "node-A"; "node-A" `children` list is updated atomically to include Y's `trace_id`.
3. "node-A" now has `children: ["X", "Y"]` — length 2, so it is a fork node.
4. `TopologyBuilder` calls `CausalDAG.get_session_dag/1` and reads "node-A" with `children: ["X", "Y"]`.
5. `TopologyBuilder` generates two edge descriptors: `{from: "node-A", to: "X"}` and `{from: "node-A", to: "Y"}`.
6. The topology canvas renders "node-A" with two outgoing lines.

## Alternate Flows
### A1: Three or more children create a wider fan-out
Condition: Three or more nodes declare the same `parent_step_id`.
Steps:
1. Each insertion atomically appends the new `trace_id` to the parent's `children` list.
2. `TopologyBuilder` generates one edge descriptor per entry in `children`.
3. The canvas renders N outgoing lines from the fork node.

## Failure Flows
### F1: Node with exactly one child is not rendered as a fork
Condition: A node has `children: ["B"]` — a single-element list.
Steps:
1. `TopologyBuilder` reads the node and finds `children` length == 1.
2. One edge descriptor is generated: `{from: node.trace_id, to: "B"}`.
3. The canvas renders a linear step with a single outgoing edge.
Result: No fork visualization is applied; the node is rendered as a standard linear step.

## Gherkin Scenarios

### S1: Parent acquires two children and is rendered as a fork
```gherkin
Scenario: Fork node with two children generates two edges
  Given session "sess-fork" has node "node-A" in ETS with children: []
  And node "node-X" with parent_step_id "node-A" is inserted
  And node "node-Y" with parent_step_id "node-A" is inserted
  When TopologyBuilder reads the session DAG via CausalDAG.get_session_dag/1
  Then "node-A" has children: ["node-X", "node-Y"]
  And TopologyBuilder emits edge descriptors {from: "node-A", to: "node-X"} and {from: "node-A", to: "node-Y"}
```

### S2: Single-child node is not rendered as a fork
```gherkin
Scenario: Node with one child is rendered as a linear step
  Given session "sess-fork" has node "node-A" in ETS with children: ["node-B"]
  When TopologyBuilder reads the session DAG
  Then TopologyBuilder emits exactly one edge descriptor {from: "node-A", to: "node-B"}
  And the canvas renders "node-A" with a single outgoing edge
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that inserts two children for the same parent and asserts the parent's `children` list contains both `trace_id` values after each atomic update.
- [ ] `mix test test/observatory/gateway/topology_builder_test.exs` passes a test that reads a DAG with a fork node (two children) and asserts two edge descriptors are generated.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Multiple Node structs sharing the same `parent_step_id`.
**Outputs:** Updated parent node in ETS with extended `children` list; edge descriptors from `TopologyBuilder`.
**State changes:** Parent node's `children` list in ETS is extended atomically on each child insertion.

## Traceability
- Parent FR: FR-8.5
- ADR: [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
