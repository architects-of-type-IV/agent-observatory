---
id: UC-0239
title: Render Node Fill Color According to State Field
status: draft
parent_fr: FR-8.10
adrs: [ADR-016]
---

# UC-0239: Render Node Fill Color According to State Field

## Intent
The `TopologyMap` hook must translate each node's `state` field into an exact hex fill color on the Canvas. The `:alert_entropy` state additionally requires a flashing animation applied to the node's bounding region. Any unrecognised or absent state must fall back to the idle color `#6b7280` without producing a runtime error, ensuring the canvas never enters an inconsistent rendering state.

## Primary Actor
TopologyMap Hook

## Supporting Actors
- Canvas 2D rendering context (`CanvasRenderingContext2D`)
- LiveView `topology_update` event payload (source of `state` field per node)

## Preconditions
- The `TopologyMap` hook has been initialized via `mounted()` and the animation loop is running.
- A `topology_update` event has been received containing at least one node with a `state` field.

## Trigger
`render()` is called during an animation frame following receipt of a `topology_update` event that contains node data with varying `state` values.

## Main Success Flow
1. `render()` iterates over the current node list received from the last `topology_update` payload.
2. For each node, `render()` reads the `state` field and selects the fill color from the following mapping:
   - `"idle"` → `#6b7280`
   - `"active"` → `#3b82f6`
   - `"alert_entropy"` → `#ef4444`, plus a flashing animation on the node's bounding region
   - `"schema_violation"` → `#f97316`
   - `"dead"` → `#374151`
   - `"blocked"` → `#f59e0b`
3. `render()` sets `ctx.fillStyle` to the selected color and draws the node shape.
4. For `"alert_entropy"` nodes, `render()` applies a periodic opacity or stroke animation within the node's bounding region.

## Alternate Flows
None defined — state mapping is deterministic per node.

## Failure Flows
### F1: Unrecognised state value
Condition: A node in the `topology_update` payload carries a `state` value not in the known mapping (e.g., `"unknown_future_state"` or absent).
Steps:
1. `render()` evaluates the state value against the known mapping.
2. No match is found.
3. `render()` applies the idle default `#6b7280` as the fill color.
4. No error is thrown; the animation loop continues uninterrupted.
Result: The node is rendered in gray; no crash occurs; the canvas remains consistent.

## Gherkin Scenarios

### S1: alert_entropy node rendered in red with flashing animation
```gherkin
Scenario: Node with state alert_entropy is rendered in #ef4444 with flashing
  Given the animation loop is running
  And a topology_update event delivers a node with state "alert_entropy"
  When render() is called during the next animation frame
  Then the canvas sets fillStyle to "#ef4444" for that node
  And a flashing animation is applied to the node's bounding region
```

### S2: Unknown state falls back to idle color without error
```gherkin
Scenario: Node with unrecognised state is rendered in idle gray
  Given the animation loop is running
  And a topology_update event delivers a node with state "unknown_future_state"
  When render() is called during the next animation frame
  Then the canvas sets fillStyle to "#6b7280" for that node
  And no runtime error is thrown
  And the animation loop continues normally
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/hooks/topology_map_test.exs` passes a test that delivers a `topology_update` event with a node in each known state and asserts the correct hex fill color is applied for each.
- [ ] `mix test test/observatory_web/hooks/topology_map_test.exs` passes a test that delivers a `topology_update` event with a node carrying an unknown state and asserts `fillStyle` is set to `#6b7280` with no exception thrown.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `topology_update` event payload containing node objects with `state` field.
**Outputs:** Canvas fill color per node; flashing animation for `:alert_entropy` nodes.
**State changes:** Canvas rendering context `fillStyle` updated per node during each render call.

## Traceability
- Parent FR: FR-8.10
- ADR: [ADR-016](../../decisions/ADR-016-canvas-topology-renderer.md)
