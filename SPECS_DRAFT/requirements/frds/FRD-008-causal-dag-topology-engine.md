---
id: FRD-008
title: Causal DAG and Topology Engine Functional Requirements
date: 2026-02-22
status: draft
source_adr: [ADR-016, ADR-017]
related_rule: []
---

# FRD-008: Causal DAG and Topology Engine

## Purpose

The Causal DAG and Topology Engine gives operators a live, causally-accurate graph of agent activity within a session. It consists of two cooperating subsystems: `Observatory.Mesh.CausalDAG`, which maintains an ETS-backed directed acyclic graph of all DecisionLog steps for each active session, and the Canvas-based topology renderer, which visualises that graph in the Fleet Command view. Together they transform a raw stream of DecisionLog messages into a queryable graph structure and a clickable, colour-coded topology map.

The engine is designed to handle out-of-order message arrival, detect causal cycles before they corrupt the graph, and broadcast incremental deltas so that multiple subscribers receive a consistent view without each rebuilding the DAG from scratch. The rendering side is implemented as a LiveView JS hook backed by the Canvas API, with no external npm dependencies in Phase 1.

## Functional Requirements

### FR-8.1: Module Location and ETS Table Structure

`Observatory.Mesh.CausalDAG` MUST be implemented in `lib/observatory/mesh/causal_dag.ex`. It MUST maintain one ETS table per active session. Each table entry MUST use the composite key `{session_id, trace_id}` and MUST store a Node struct with the following fields: `trace_id` (string), `parent_step_id` (string or nil), `agent_id` (string), `intent` (string), `confidence_score` (float), `entropy_score` (float), `action_status` (atom), `timestamp` (DateTime), and `children` (list of trace_id strings). No field in the Node struct MAY be omitted at insert time; callers MUST supply all fields or receive an `{:error, :missing_fields}` tuple.

**Positive path**: A new DecisionLog message arrives; `CausalDAG.insert/2` is called with `session_id` and a Node struct containing all required fields; the node is written to the ETS table under key `{session_id, trace_id}`.

**Negative path**: A Node struct missing one or more required fields is passed to `CausalDAG.insert/2`; the function returns `{:error, :missing_fields}` and writes nothing to ETS.

---

### FR-8.2: Root Node Detection

A node whose `parent_step_id` field is `nil` MUST be treated as a root node. `CausalDAG.insert/2` MUST insert such a node directly into the ETS table without consulting the orphan buffer. A session MAY have multiple root nodes, each representing a separate initial trigger that arrived with no declared causal predecessor. Root nodes MUST have an empty `children` list at the time of insertion; the list is populated as child nodes arrive.

**Positive path**: A DecisionLog message arrives with `parent_step_id: nil`; the node is inserted as a root, recorded with `children: []`, and included in the next DAG delta broadcast under `added_nodes`.

**Negative path**: A node is inserted with `parent_step_id: nil` when a root for this session already exists; the second root MUST be inserted normally as an additional root — `CausalDAG` MUST NOT reject it or coerce it into the existing root's subtree.

---

### FR-8.3: Orphan Buffer and 30-Second Timeout

When `CausalDAG.insert/2` receives a node whose `parent_step_id` is non-nil but whose parent `trace_id` is not yet present in the session's ETS table, the node MUST be placed into an in-memory orphan buffer keyed by `{session_id, parent_step_id}`. The buffer entry MUST record the UTC timestamp of insertion. If the referenced parent node arrives within 30 seconds, the orphan MUST be retroactively attached to that parent: the parent's `children` list is updated, the orphaned node is moved from the buffer into ETS, and a DAG delta broadcast is emitted for the attachment. If 30 seconds elapse without the parent arriving, the orphan MUST be attached to the session's first root node with a warning flag of `:orphan` stored on the node struct, and a delta broadcast MUST be emitted for the attachment. The orphan buffer MUST NOT grow unboundedly; entries older than 30 seconds MUST be resolved and removed.

**Positive path**: Node B arrives with `parent_step_id` pointing to trace_id A, which is not yet in ETS; B is buffered. Node A arrives 8 seconds later; B is attached to A's `children` list; both the attachment and node B's ETS entry are written; a delta broadcast is emitted.

**Negative path**: Node B is buffered for 31 seconds with no parent arrival; B is attached to the session root with `orphan: true`; a delta broadcast is emitted; the buffer entry is cleared.

---

### FR-8.4: Cycle Prevention

`CausalDAG.insert/2` MUST reject any node insertion that would create a cycle in the DAG. Before writing a node to ETS, the module MUST walk the ancestor chain of `parent_step_id` upward; if the incoming `trace_id` appears anywhere in that chain, the insertion MUST be aborted and the function MUST return `{:error, :cycle_detected}`. This check MUST be performed for every non-root insertion. No cycle detection is required for root nodes (`parent_step_id == nil`).

**Positive path**: Node C arrives with `parent_step_id` pointing to B, which has `parent_step_id` pointing to A; A's ancestor chain is nil; no cycle is found; C is inserted normally.

**Negative path**: An agent emits a node with `trace_id` equal to an ancestor's `trace_id` (e.g., node A declares its parent as C, where C is already a descendant of A); `CausalDAG.insert/2` detects the cycle and returns `{:error, :cycle_detected}`; nothing is written to ETS.

---

### FR-8.5: Fork Node Semantics

A node whose `children` list contains two or more `trace_id` entries MUST be treated as a fork node. The topology renderer MUST render a fork node as a single parent node with N outgoing edges, one per child — a 1→N visual fan-out. `CausalDAG` MUST update a node's `children` list atomically each time a new child is attached. No separate data structure is required; fork status is derived at read time by inspecting `children` length.

**Positive path**: Node A has `children: ["B", "C"]`; `TopologyBuilder` reads A and generates two edges, A→B and A→C; the topology map renders A as a fork with two outgoing lines.

**Negative path**: A node with a single child (`children: ["B"]`) MUST NOT be rendered as a fork; it MUST be rendered as a linear step with one outgoing edge.

---

### FR-8.6: Public API — get_session_dag/1

`CausalDAG.get_session_dag/1` MUST accept a `session_id` string and MUST return a full adjacency map for that session as `{:ok, %{trace_id => %Node{}}}`. The returned map MUST include every node currently in ETS for that session, with each node's `children` list reflecting all attachments made up to the moment of the call. If the session has no ETS table (unknown or already pruned), the function MUST return `{:error, :session_not_found}`. This function is the primary read API for the Session Drill-down view and for `TopologyBuilder`.

**Positive path**: A caller invokes `CausalDAG.get_session_dag("sess-abc")`; the ETS table contains 12 nodes; the function returns `{:ok, %{"trace-1" => %Node{...}, ...}}` with all 12 entries.

**Negative path**: A caller invokes `CausalDAG.get_session_dag("sess-unknown")`; no ETS table exists for that session_id; the function returns `{:error, :session_not_found}`.

---

### FR-8.7: DAG Delta Broadcast

`CausalDAG` MUST broadcast a delta message to the PubSub topic `"session:dag:{session_id}"` after every successful node insertion and after every orphan attachment. The broadcast payload MUST be a map with the keys `event` (string `"dag_delta"`), `session_id` (string), `added_nodes` (list of Node maps), `updated_nodes` (list of Node maps reflecting `children` list changes), and `added_edges` (list of maps, each with keys `from` and `to` holding `trace_id` strings). A broadcast MUST NOT be emitted for rejected insertions (cycle detected, missing fields) or for buffer placements that have not yet been resolved.

**Positive path**: Node D is inserted as a child of C; `CausalDAG` broadcasts `%{event: "dag_delta", session_id: "sess-abc", added_nodes: [D], updated_nodes: [C], added_edges: [%{from: C.trace_id, to: D.trace_id}]}` to `"session:dag:sess-abc"`.

**Negative path**: A node insertion is rejected due to a cycle; no broadcast is emitted; the PubSub topic remains unaffected.

---

### FR-8.8: ETS Pruning on Session Terminal

`CausalDAG` MUST subscribe to session lifecycle events. When a `control.is_terminal == true` signal is received for a `session_id`, `CausalDAG` MUST schedule deletion of that session's ETS table exactly 5 minutes after the terminal signal is received. During those 5 minutes the table MUST remain queryable via `get_session_dag/1` to allow in-flight drill-down views to complete. After 5 minutes, the ETS table MUST be deleted and `get_session_dag/1` for that session MUST return `{:error, :session_not_found}`.

**Positive path**: Session "sess-xyz" receives `is_terminal: true` at 14:00:00 UTC; the ETS table is queried successfully at 14:04:00 UTC; at 14:05:00 UTC the table is deleted; a query at 14:05:01 UTC returns `{:error, :session_not_found}`.

**Negative path**: A second `is_terminal: true` signal arrives for the same session before the 5-minute timer fires; `CausalDAG` MUST NOT reset the timer — the original scheduled deletion MUST proceed unchanged.

---

### FR-8.9: topology_map.js Hook Structure

The file `assets/js/hooks/topology_map.js` MUST implement a LiveView JS hook named `TopologyMap` using the Canvas API with no external npm dependencies. The hook MUST implement four methods: `mounted()`, `render()`, `handleClick(e)`, and `startAnimationLoop()`. `mounted()` MUST obtain the 2D canvas rendering context via `this.el.querySelector('canvas').getContext('2d')`, register a handler for the `"topology_update"` LiveView event via `this.handleEvent(...)`, attach a click listener on the canvas element, and call `startAnimationLoop()`. `startAnimationLoop()` MUST drive redraws via `requestAnimationFrame`. `render()` MUST apply a force-directed layout algorithm and draw all current nodes and edges to the canvas. The hook MUST NOT import or require any npm package.

**Positive path**: LiveView mounts a component containing `<canvas>` and the `phx-hook="TopologyMap"` attribute; the browser calls `mounted()`; the animation loop starts; subsequent `topology_update` events cause the canvas to redraw with updated node and edge positions.

**Negative path**: The `mounted()` lifecycle runs but `this.el.querySelector('canvas')` returns null (canvas element absent from template); the hook MUST log an error and abort initialization without throwing an uncaught exception that would crash the LiveView page.

---

### FR-8.10: Node State Color Mapping

`topology_map.js` MUST render each node's fill color according to its `state` field using the following exact mapping: `:idle` → `#6b7280`, `:active` → `#3b82f6`, `:alert_entropy` → `#ef4444` with a CSS flashing animation applied to the canvas element or the node's bounding region, `:schema_violation` → `#f97316`, `:dead` → `#374151`, `:blocked` → `#f59e0b`. Any node whose `state` field is absent or carries an unrecognised value MUST be rendered using the `:idle` color `#6b7280` as a safe default. No state transition MUST produce a runtime error.

**Positive path**: A `topology_update` event delivers a node with `state: "alert_entropy"`; the hook renders that node in `#ef4444` and starts a flashing animation on that node.

**Negative path**: A `topology_update` event delivers a node with `state: "unknown_future_state"`; the hook renders that node in `#6b7280` (idle default) without throwing an error.

---

### FR-8.11: Edge Click pushEvent Contract

`topology_map.js` MUST implement hit detection for edges in `handleClick(e)`. When a click event falls within the hit target of an edge (a configurable pixel-width tolerance around the edge line), the hook MUST call `this.pushEvent("edge_selected", payload)` where `payload` is a map containing `traffic_volume` (number), `latency_ms` (number), and `status` (string). When a click event falls on a node rather than an edge, the hook MUST call `this.pushEvent("node_selected", %{trace_id: string})`. If a click lands on neither a node nor an edge, the hook MUST take no action and MUST NOT push any event.

**Positive path**: An operator clicks an edge between node A and node B; hit detection succeeds; `pushEvent("edge_selected", %{traffic_volume: 42, latency_ms: 18, status: "active"})` is called; the LiveView handler receives the event and updates the inspector panel.

**Negative path**: An operator clicks on empty canvas space with no node or edge within tolerance; no `pushEvent` is called; the UI state is unchanged.

---

### FR-8.12: TopologyBuilder Reads from CausalDAG

`Observatory.Gateway.TopologyBuilder` MUST be implemented in `lib/observatory/gateway/topology_builder.ex`. It MUST read agent and session graph data by calling `CausalDAG.get_session_dag/1` for each active session. From the returned adjacency map it MUST derive a list of node descriptors (each including `trace_id`, `agent_id`, `state`, and position hint) and a list of edge descriptors (each including `from`, `to`, `traffic_volume`, `latency_ms`, and `status`). `TopologyBuilder` MUST NOT maintain its own copy of DAG node data; all graph structure MUST be sourced from `CausalDAG`.

**Positive path**: `TopologyBuilder` is triggered by a DAG delta event; it calls `CausalDAG.get_session_dag/1` for the affected session; it computes the updated node and edge lists; it broadcasts to `"gateway:topology"`.

**Negative path**: `CausalDAG.get_session_dag/1` returns `{:error, :session_not_found}` for a session that was pruned; `TopologyBuilder` MUST skip that session silently and MUST NOT crash or emit a partial broadcast for it.

---

### FR-8.13: gateway:topology PubSub Topic

`TopologyBuilder` MUST broadcast all topology updates to the PubSub topic `"gateway:topology"`. The Fleet Command LiveView MUST subscribe to `"gateway:topology"` during `mount/3` and MUST call `push_event(socket, "topology_update", %{nodes: nodes, edges: edges})` on receipt of each broadcast, forwarding the payload to the `TopologyMap` JS hook. The `"gateway:topology"` topic MUST be the sole channel through which the Fleet Command view learns of node and edge state changes. Direct ETS reads from Fleet Command LiveView are not permitted.

**Positive path**: An agent transitions to `:active` state; `TopologyBuilder` broadcasts an updated nodes list to `"gateway:topology"`; Fleet Command LiveView receives the broadcast and calls `push_event/3`; the canvas redraws the node in blue within one animation frame.

**Negative path**: `TopologyBuilder` crashes between two DAG updates; the Fleet Command view receives no broadcast for that interval; the canvas retains the last known state without error; when `TopologyBuilder` restarts, it broadcasts a full snapshot on its first successful run.

## Out of Scope (Phase 1)

- React Flow migration (triggered only when >3 interactive requirements require >200 lines of custom Canvas JS)
- Zoom and pan gestures beyond basic Canvas transform
- Nested sub-graph expansion within the topology map
- Custom node editor modals
- Persistent layout memory across page reloads
- Option C hybrid entropy: agent self-report + Gateway validation divergence events

## Related ADRs

- [ADR-016](../../decisions/ADR-016-canvas-topology-renderer.md) -- Canvas-based topology renderer; defines JS hook structure, node state colors, PubSub topic, and Phase 2 migration trigger
- [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md) -- Causal DAG construction; defines ETS data model, orphan buffer, cycle prevention, delta broadcast format, and session pruning
