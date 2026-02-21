---
id: UC-0238
title: Initialize the TopologyMap LiveView JS Hook on Canvas Mount
status: draft
parent_fr: FR-8.9
adrs: [ADR-016]
---

# UC-0238: Initialize the TopologyMap LiveView JS Hook on Canvas Mount

## Intent
The `TopologyMap` LiveView JS hook must initialize a Canvas 2D rendering context, register for `topology_update` events from the server, attach a click listener on the canvas element, and start the `requestAnimationFrame`-driven animation loop — all without importing any external npm package. If the canvas element is absent from the DOM at mount time, the hook must log an error and abort cleanly without crashing the LiveView page.

## Primary Actor
TopologyMap Hook

## Supporting Actors
- Canvas 2D rendering context (`CanvasRenderingContext2D`)
- LiveView JS event system (`this.handleEvent`, `this.pushEvent`)
- Browser `requestAnimationFrame` API

## Preconditions
- The Fleet Command LiveView has rendered the `<canvas>` element with the `phx-hook="TopologyMap"` attribute before `mounted()` is called.
- The hook file `assets/js/hooks/topology_map.js` exports a `TopologyMap` object with `mounted`, `render`, `handleClick`, and `startAnimationLoop` methods.
- No external npm dependency is imported by the hook file.

## Trigger
LiveView calls the `mounted()` lifecycle method on the `TopologyMap` hook after the component containing `<canvas>` is inserted into the DOM.

## Main Success Flow
1. `mounted()` is called by the LiveView framework.
2. `mounted()` calls `this.el.querySelector('canvas').getContext('2d')` to obtain the 2D rendering context; the context reference is stored on the hook instance.
3. `mounted()` calls `this.handleEvent("topology_update", handler)` to register the topology update handler.
4. `mounted()` attaches a `click` event listener on the canvas element, bound to `this.handleClick`.
5. `mounted()` calls `this.startAnimationLoop()`.
6. `startAnimationLoop()` calls `requestAnimationFrame(renderFn)` recursively to drive continuous redraws.
7. Subsequent `topology_update` events from the server trigger `render()`, which applies a force-directed layout and draws nodes and edges to the canvas.

## Alternate Flows
None defined for this UC.

## Failure Flows
### F1: Canvas element absent from DOM at mount time
Condition: `this.el.querySelector('canvas')` returns `null` because the `<canvas>` element is missing from the template.
Steps:
1. `mounted()` checks the result of `querySelector('canvas')`.
2. A console error is logged (e.g., `console.error("TopologyMap: canvas element not found")`).
3. `mounted()` returns without calling `getContext('2d')`, `handleEvent`, or `startAnimationLoop`.
4. No uncaught exception is thrown; the LiveView page continues to function.
Result: The topology map is non-functional but the page does not crash.

## Gherkin Scenarios

### S1: Successful hook initialization with canvas present
```gherkin
Scenario: TopologyMap hook initializes correctly when canvas element is present
  Given the Fleet Command LiveView renders a component with a <canvas> element
  And the component carries the attribute phx-hook="TopologyMap"
  When the LiveView framework calls mounted() on the TopologyMap hook
  Then mounted() obtains the 2D rendering context via querySelector('canvas').getContext('2d')
  And a topology_update event handler is registered via this.handleEvent
  And a click listener is attached to the canvas element
  And startAnimationLoop() is called which begins requestAnimationFrame redraws
```

### S2: Canvas element absent — hook aborts without crashing
```gherkin
Scenario: TopologyMap hook aborts gracefully when canvas element is missing
  Given the Fleet Command LiveView renders a component without a <canvas> element
  And the component carries the attribute phx-hook="TopologyMap"
  When the LiveView framework calls mounted() on the TopologyMap hook
  Then a console error is logged indicating the canvas element was not found
  And no uncaught exception is thrown
  And the LiveView page remains functional
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/hooks/topology_map_test.exs` passes a test that mounts a component with a `<canvas>` element and asserts that `handleEvent("topology_update", ...)` was called during `mounted()` and that the animation loop is active.
- [ ] `mix test test/observatory_web/hooks/topology_map_test.exs` passes a test that mounts the hook without a `<canvas>` element present and asserts no uncaught exception is thrown and a console error is logged.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** DOM subtree containing (or missing) a `<canvas>` element; `topology_update` events from the server.
**Outputs:** Running animation loop; registered event and click handlers; canvas renders on each frame.
**State changes:** Hook instance stores canvas context reference and node/edge data received from server events.

## Traceability
- Parent FR: FR-8.9
- ADR: [ADR-016](../../decisions/ADR-016-canvas-topology-renderer.md)
