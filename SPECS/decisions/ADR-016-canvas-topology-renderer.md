---
id: ADR-016
title: Canvas-Based Topology Map Renderer
date: 2026-02-21
status: proposed
related_tasks: []
parent: ADR-013
superseded_by: null
---
# ADR-016 Canvas-Based Topology Map Renderer
[2026-02-21] proposed

## Related ADRs
- [ADR-013](ADR-013-hypervisor-platform-scope.md) Hypervisor Platform Scope (parent)
- [ADR-017](ADR-017-causal-dag-parent-step-id.md) Causal DAG via parent_step_id
- [ADR-022](ADR-022-six-view-ui-architecture.md) Six-View UI Information Architecture

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief §4.3 | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | Topology Map requirements |

## Context

The Fleet Command view requires a live-updating graph of all agents in the mesh. Nodes represent agents; edges represent active message flows. Operators need to:

- See node states change in real-time (idle → active → alert)
- Click edges to inspect traffic volume/latency/status
- Drill into clusters without leaving the map context
- Receive alarm overlays directly on nodes/edges

The central question is the rendering engine. The brief mentions "WebGL or Canvas-based engine (like React Flow or G6)." These are significantly different in implementation complexity, performance ceiling, and Phoenix LiveView integration model.

## Options Considered

1. **SVG via LiveView** — Render graph as SVG elements managed by LiveView diffs. Simple to implement; no external JS library.
   - Pro: Pure LiveView. No JS bundle dependency. Diff-based updates.
   - Con: SVG performance degrades significantly above ~200 nodes due to DOM pressure. No hardware acceleration.

2. **D3.js via LiveView JS hooks** — LiveView pushes graph data; a D3 hook renders SVG/Canvas. D3 handles layout algorithms.
   - Pro: Flexible, battle-tested, large community.
   - Con: D3 is a library for data visualization, not a graph component. Building edge-click interactions, hierarchical drill-down, and HUD overlays from scratch is significant JS work.

3. **React Flow embedded via LiveView JS hook** — React Flow is a purpose-built interactive node-edge graph library. Embed it in a LiveView hook; LiveView pushes state updates via `pushEvent`/`handleEvent`.
   - Pro: Interactive by default (drag, zoom, click). Edge and node click handlers built-in. Hierarchical sub-graphs supported. Active maintenance.
   - Con: Adds React as a JS dependency. Bundle size increases. LiveView → React data bridge requires careful design.

4. **Canvas API (hand-rolled) via LiveView JS hook** — Custom Canvas renderer with manual hit detection, force-directed layout, and animation loop.
   - Pro: Zero external JS dependency. Full control over rendering. Handles 1000+ nodes smoothly with hardware acceleration.
   - Con: Substantial JS implementation effort. No built-in interaction model — click detection, zoom, pan must all be custom.

5. **G6 or Cytoscape.js via LiveView JS hook** — Purpose-built graph visualization libraries with Canvas/WebGL backends.
   - Pro: Hardware-accelerated. Rich interaction model. Specifically designed for network graphs.
   - Con: Additional bundle dependency. Less common in Phoenix ecosystems; less prior art.

## Decision

**Two-phase approach:**

**Phase 1 (v1):** Canvas API via LiveView JS hook (Option 4), scoped to the essentials: force-directed layout, node state colors, edge click, basic zoom/pan. This gets a working topology map without external dependencies.

**Phase 2 (v2, if warranted):** Migrate to React Flow (Option 3) when interactive requirements grow beyond what the hand-rolled Canvas can support cleanly (e.g., nested sub-graph expansion, custom node editor modals, persistent layout memory).

The phase boundary is triggered by: >3 interactive requirements that would require >200 lines of custom JS in the Canvas implementation.

**Phase 1 architecture:**

```javascript
// assets/js/hooks/topology_map.js
const TopologyMap = {
  mounted() {
    this.canvas = this.el.querySelector('canvas')
    this.ctx = this.canvas.getContext('2d')
    this.nodes = []
    this.edges = []
    this.handleEvent("topology_update", ({ nodes, edges }) => {
      this.nodes = nodes
      this.edges = edges
      this.render()
    })
    this.canvas.addEventListener('click', this.handleClick.bind(this))
    this.startAnimationLoop()
  },
  render() { /* force-directed layout + draw nodes/edges */ },
  handleClick(e) { /* hit detection → pushEvent("node_selected") or ("edge_selected") */ },
  startAnimationLoop() { /* requestAnimationFrame loop for smooth state transitions */ }
}
```

**LiveView side:** `Fleet Command` view subscribes to `"gateway:topology"` PubSub topic. On each update, calls `push_event(socket, "topology_update", %{nodes: nodes, edges: edges})`.

**Node state colors:**
- `:idle` → grey (`#6b7280`)
- `:active` → blue (`#3b82f6`)
- `:alert_entropy` → flashing red (`#ef4444`, CSS animation)
- `:schema_violation` → orange (`#f97316`)
- `:dead` → dim (`#374151`)
- `:blocked` → amber (`#f59e0b`)

## Rationale

Starting with Canvas avoids a React dependency in a Phoenix LiveView codebase that has no existing React components. The LiveView `push_event` → Canvas hook pattern is well-established. The phase 2 migration path is defined but not forced on v1.

The phase trigger (>3 interactive requirements) is explicit so the team knows exactly when to migrate rather than endlessly patching the Canvas implementation.

## Consequences

- New JS hook: `assets/js/hooks/topology_map.js`
- New LiveView component: `ObservatoryWeb.Components.TopologyMap`
- New PubSub topic: `"gateway:topology"` — Gateway broadcasts node/edge state changes
- New Gateway module: `Observatory.Gateway.TopologyBuilder` — computes node/edge data from Capability Map
- No new npm dependencies in Phase 1
- React Flow migration path documented but not scheduled
