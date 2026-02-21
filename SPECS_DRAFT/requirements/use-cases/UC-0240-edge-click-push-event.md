---
id: UC-0240
title: Dispatch pushEvent on Canvas Edge or Node Click
status: draft
parent_fr: FR-8.11
adrs: [ADR-016]
---

# UC-0240: Dispatch pushEvent on Canvas Edge or Node Click

## Intent
`handleClick(e)` must translate a canvas mouse event into either an `edge_selected` or `node_selected` LiveView push event, or take no action if the click lands on empty space. Edge hit detection uses a configurable pixel-width tolerance around each edge line. Node hit detection takes precedence when a click could match both. An empty-space click must never push a spurious event.

## Primary Actor
TopologyMap Hook

## Supporting Actors
- Canvas 2D rendering context (used for coordinate translation)
- LiveView event system (`this.pushEvent`)
- Fleet Command LiveView (receives pushed events and updates the inspector panel)

## Preconditions
- The `TopologyMap` hook is initialized and the animation loop is running.
- At least one `topology_update` event has been received so the hook has current node and edge positions.

## Trigger
The user clicks anywhere on the canvas element; the browser fires a `click` event that is routed to `handleClick(e)`.

## Main Success Flow
1. The operator clicks on an edge between node A and node B.
2. `handleClick(e)` converts the mouse event coordinates to canvas-local coordinates.
3. Hit detection checks whether the click falls within the pixel-width tolerance of any edge line.
4. A match is found for the edge A→B.
5. `this.pushEvent("edge_selected", {traffic_volume: 42, latency_ms: 18, status: "active"})` is called.
6. The Fleet Command LiveView handler receives the event and updates the inspector panel.

## Alternate Flows
### A1: Click lands on a node
Condition: The click coordinates fall within the bounding circle or rectangle of a node.
Steps:
1. Node hit detection finds a match for node with `trace_id` "node-X".
2. `this.pushEvent("node_selected", {trace_id: "node-X"})` is called.
3. The LiveView handler receives the event and updates the inspector panel for that node.

## Failure Flows
### F1: Click lands on empty canvas space
Condition: The click coordinates do not fall within any node or within the tolerance of any edge.
Steps:
1. `handleClick(e)` runs hit detection for both nodes and edges; no match is found.
2. `handleClick(e)` returns without calling `pushEvent`.
3. No UI state changes occur.
Result: The inspector panel is unchanged; no spurious event is pushed to the LiveView.

## Gherkin Scenarios

### S1: Edge click pushes edge_selected event with payload
```gherkin
Scenario: Operator clicks an edge and edge_selected is pushed to LiveView
  Given the topology map has edge A-to-B with traffic_volume 42, latency_ms 18, status "active"
  And the click coordinates fall within the hit tolerance of edge A-to-B
  When the operator clicks on the canvas at those coordinates
  Then pushEvent is called with event name "edge_selected"
  And the payload contains traffic_volume: 42, latency_ms: 18, status: "active"
```

### S2: Node click pushes node_selected event with trace_id
```gherkin
Scenario: Operator clicks a node and node_selected is pushed to LiveView
  Given the topology map has node with trace_id "node-X" at canvas coordinates (100, 150)
  And the click coordinates fall within the bounding region of "node-X"
  When the operator clicks the canvas at (100, 150)
  Then pushEvent is called with event name "node_selected"
  And the payload contains trace_id: "node-X"
```

### S3: Empty-space click produces no pushEvent
```gherkin
Scenario: Click on empty canvas space pushes no event
  Given the topology map has nodes and edges not near canvas coordinate (500, 500)
  When the operator clicks the canvas at (500, 500)
  Then no pushEvent call is made
  And the inspector panel state is unchanged
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/hooks/topology_map_test.exs` passes a test that simulates a click within edge hit tolerance and asserts `pushEvent("edge_selected", ...)` is called with the correct `traffic_volume`, `latency_ms`, and `status` fields.
- [ ] `mix test test/observatory_web/hooks/topology_map_test.exs` passes a test that simulates a click on a node and asserts `pushEvent("node_selected", %{trace_id: ...})` is called.
- [ ] `mix test test/observatory_web/hooks/topology_map_test.exs` passes a test that simulates a click on empty canvas space and asserts `pushEvent` is not called.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `MouseEvent` with `clientX`/`clientY`; current node/edge positions from last `topology_update`.
**Outputs:** `pushEvent("edge_selected", payload)` or `pushEvent("node_selected", payload)` or no action.
**State changes:** None on the hook itself; LiveView inspector panel updates on receipt of the event.

## Traceability
- Parent FR: FR-8.11
- ADR: [ADR-016](../../decisions/ADR-016-canvas-topology-renderer.md)
