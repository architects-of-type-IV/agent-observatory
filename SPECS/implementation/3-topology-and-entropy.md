---
type: phase
id: 3
title: topology-and-entropy
date: 2026-02-22
status: pending
links:
  adr: [ADR-016, ADR-017, ADR-018]
depends_on:
  - phase: 1
  - phase: 2
---

# Phase 3: Topology & Entropy

## Overview

This phase builds the two subsystems that transform validated DecisionLog messages into a live, causally-accurate visual graph and an objective loop-detection signal. The first subsystem is `Observatory.Mesh.CausalDAG` — an ETS-backed directed acyclic graph that maintains one adjacency table per active session, handling out-of-order arrival via a 30-second orphan buffer, enforcing acyclicity via ancestor-chain traversal, and broadcasting incremental deltas over `"session:dag:{session_id}"` PubSub. Alongside it, `Observatory.Gateway.TopologyBuilder` reads from `CausalDAG` and publishes node and edge descriptor lists to the `"gateway:topology"` PubSub topic, which the Fleet Command LiveView forwards to the `TopologyMap` Canvas JS hook — a zero-npm-dependency renderer with force-directed layout, state-based node coloring, and edge click hit detection. The second subsystem is `Observatory.Gateway.EntropyTracker` — a GenServer with a private ETS sliding window (default size 5) of `{intent, tool_call, action_status}` tuples per session. On each `record_and_score/2` call it computes a uniqueness ratio, applies LOOP/WARNING/Normal classification against runtime-configurable thresholds, broadcasts `EntropyAlertEvent` and topology state updates where appropriate, and returns a structured severity tuple so `SchemaInterceptor` can overwrite the `cognition.entropy_score` field with a Gateway-authoritative value.

This phase depends on both preceding phases. Phase 1 (`decision-log-schema`) provides the `%Observatory.Mesh.DecisionLog{}` struct whose fields — `meta.trace_id`, `meta.parent_step_id`, `cognition.intent`, `action.tool_call`, `action.status`, and `control.is_terminal` — are the direct input to both CausalDAG node construction and EntropyTracker tuple formation. Phase 2 (`gateway-core`) provides the `Observatory.Gateway.SchemaInterceptor` pipeline where `EntropyTracker.record_and_score/2` is called synchronously after each successful schema validation, and where the returned score overwrites the agent's self-reported `cognition.entropy_score` before downstream broadcast. Without the validated `%DecisionLog{}` struct and the `SchemaInterceptor` wiring point, neither DAG insertion nor entropy accumulation can occur in production.

### ADR Links
- [ADR-016](../decisions/ADR-016-canvas-topology-renderer.md)
- [ADR-017](../decisions/ADR-017-causal-dag-parent-step-id.md)
- [ADR-018](../decisions/ADR-018-entropy-score-loop-detection.md)

---

## 3.1 CausalDAG ETS Store

- [ ] **Section 3.1 Complete**

This section creates the `Observatory.Mesh.CausalDAG` GenServer at `lib/observatory/mesh/causal_dag.ex` and establishes the core ETS data model. It implements the Node struct definition, per-session table creation, missing-field guard, root node detection, the 30-second orphan buffer with its resolution timer, and cycle prevention via ancestor-chain traversal. These four tasks (covering FR-8.1 through FR-8.4) must complete before any DAG query API, TopologyBuilder, or EntropyTracker integration can wire in, because every downstream subsystem depends on nodes being correctly inserted, rooted, and acyclic.

### 3.1.1 Node Struct & ETS Table Setup

- [ ] **Task 3.1.1 Complete**
- **Governed by:** ADR-017
- **Parent UCs:** UC-0230, UC-0231

Define the `%Observatory.Mesh.CausalDAG.Node{}` struct with all nine required fields and implement `CausalDAG.insert/2` for the root and non-orphan paths. Each active session gets its own ETS table created on demand. The function validates field presence before any ETS write and inserts root nodes (where `parent_step_id` is nil) directly without touching the orphan buffer. For non-root nodes whose parent is present in ETS, the parent's `children` list is updated atomically and a delta broadcast is emitted.

- [ ] 3.1.1.1 Create `lib/observatory/mesh/causal_dag.ex` with `use GenServer`, define `defmodule Observatory.Mesh.CausalDAG`, and add `defmodule Node` inside it with `defstruct trace_id: nil, parent_step_id: nil, agent_id: nil, intent: nil, confidence_score: nil, entropy_score: nil, action_status: nil, timestamp: nil, children: [], orphan: false`; start the GenServer with `start_link/1` and `init/1` that creates an ETS table `:causal_dag_session_registry` with type `:set` to track which session table names exist, then confirm `mix compile --warnings-as-errors` passes `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.1.2 Implement `def insert(session_id, %Node{} = node)` as a public function that calls `GenServer.call(__MODULE__, {:insert, session_id, node})`; implement `handle_call({:insert, session_id, node}, _from, state)` that first calls a private `validate_fields/1` — returning `{:reply, {:error, :missing_fields}, state}` if any of the nine required struct fields is nil (excluding `parent_step_id`, which may be nil for roots, and `children` and `orphan`, which have defaults); on validation pass, call `ensure_session_table(session_id)` to create a new ETS table named `:"dag_#{session_id}"` with type `:set` if it does not yet exist, registering the name in `:causal_dag_session_registry` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.1.3 Inside `handle_call({:insert, ...})`, after table setup: if `node.parent_step_id == nil`, write the node directly to ETS via `:ets.insert(table_name, {node.trace_id, node})`, then call `broadcast_delta(session_id, [node], [], [])` and return `{:reply, :ok, state}`; if `node.parent_step_id != nil` and the parent IS present in ETS (via `:ets.lookup(table_name, node.parent_step_id)`), write the node to ETS, update the parent's `children` list atomically with `:ets.update_element/3`, then call `broadcast_delta(session_id, [node], [updated_parent], [%{from: node.parent_step_id, to: node.trace_id}])` and return `{:reply, :ok, state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.1.4 Create `test/observatory/mesh/causal_dag_test.exs` with `use ExUnit.Case, async: false`; write a test `"insert/2 with all required fields writes node to ETS and returns :ok"` that starts `CausalDAG` via `start_supervised!({CausalDAG, []})`, builds a `%Node{}` with all nine non-default fields populated and `parent_step_id: nil`, calls `CausalDAG.insert("sess-t1", node)`, asserts the return value is `:ok`, then calls `CausalDAG.get_session_dag("sess-t1")` and asserts the returned map contains the node's `trace_id`; write a second test `"insert/2 with missing agent_id returns {:error, :missing_fields}"` that calls `CausalDAG.insert` with a node where `agent_id: nil` and asserts `{:error, :missing_fields}` is returned and ETS is unchanged `done_when: "mix test test/observatory/mesh/causal_dag_test.exs"`

### 3.1.2 Orphan Buffer (30-Second Window)

- [ ] **Task 3.1.2 Complete**
- **Governed by:** ADR-017
- **Parent UCs:** UC-0232

When a non-root node arrives whose `parent_step_id` is not yet present in the session ETS table, the node must be placed into an in-memory orphan buffer. If the parent subsequently arrives within 30 seconds, the orphan is promoted — moved from buffer to ETS, the parent's `children` list updated, and a delta broadcast emitted. If 30 seconds elapse without the parent arriving, the orphan is attached to the session's first root node with `orphan: true` and a delta broadcast is emitted. The buffer must never hold resolved or expired entries.

- [ ] 3.1.2.1 In `init/1`, add an ETS table `:causal_dag_orphan_buffer` with type `:bag` to hold orphaned nodes keyed by `{session_id, parent_step_id}`; each entry is a tuple `{{session_id, parent_step_id}, orphan_node, inserted_at_monotonic}` where `inserted_at_monotonic` is `System.monotonic_time(:millisecond)`; schedule the first orphan check via `Process.send_after(self(), :check_orphans, 5_000)` inside `init/1` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.2.2 In `handle_call({:insert, session_id, node}, ...)`: when `node.parent_step_id != nil` and the parent is NOT found in ETS, insert the node into `:causal_dag_orphan_buffer` under key `{session_id, node.parent_step_id}` with the current monotonic timestamp; return `{:reply, :ok, state}` without writing to the session ETS table and without broadcasting a delta; additionally, after any successful node insertion into the session ETS table, call a private `check_and_promote_orphans(session_id, node.trace_id, state)` that looks up `:causal_dag_orphan_buffer` for any orphans waiting for this `trace_id` as their parent, promotes them to ETS, updates the parent's `children` list, removes the buffer entries, and broadcasts a delta for each promoted node `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.2.3 Implement `handle_info(:check_orphans, state)` that reads all entries from `:causal_dag_orphan_buffer`, groups by `{session_id, parent_step_id}`, evicts any entry where `System.monotonic_time(:millisecond) - inserted_at_monotonic > 30_000` by finding the session's first root node (the first ETS entry with `parent_step_id: nil` in `:ets.match(session_table, {:_, %{parent_step_id: nil}})`), setting `orphan_node.orphan = true`, inserting the orphan under the root's `children` list, broadcasting a delta, and deleting the buffer entry; reschedule via `Process.send_after(self(), :check_orphans, 5_000)` before returning `{:noreply, state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.2.4 In `test/observatory/mesh/causal_dag_test.exs`, write a test `"orphan is promoted when its parent arrives within 30 seconds"` that inserts a root node, inserts a child with `parent_step_id: "missing-parent"`, then inserts the missing parent node, and asserts the child is now retrievable in the session DAG and the parent's `children` list includes the child's `trace_id`; write a second test `"orphan is attached to root with orphan: true after timeout"` that inserts a root, inserts an orphaned child with a non-existent parent, sends `:check_orphans` directly to the GenServer pid via `Process.send/2` after manually setting the buffer entry's timestamp to 31 seconds ago (using `:ets.update_element`), then calls `CausalDAG.get_session_dag/1` and asserts the orphan is present with `orphan: true` in the returned map `done_when: "mix test test/observatory/mesh/causal_dag_test.exs"`

### 3.1.3 Cycle Prevention

- [ ] **Task 3.1.3 Complete**
- **Governed by:** ADR-017
- **Parent UCs:** UC-0233

Before any non-root node is written to ETS, CausalDAG must walk the ancestor chain of the declared `parent_step_id` upward, checking whether the incoming `trace_id` appears anywhere in that chain. If a match is found, the insertion is aborted and `{:error, :cycle_detected}` is returned with no ETS modification and no broadcast. The walk terminates early on the first match (cycle found) or on reaching a root (nil `parent_step_id`) or an ETS miss (orphaned ancestor chain — treated as cycle-free).

- [ ] 3.1.3.1 Implement a private `detect_cycle(session_table, incoming_trace_id, current_parent_id, hops \\ 0)` function: base cases — if `current_parent_id == nil` return `:no_cycle`; if `hops >= 100` return `:no_cycle` (cap to prevent infinite traversal on malformed ETS state); recursive case — look up `current_parent_id` in `session_table` via `:ets.lookup/2`; if the looked-up node's `trace_id == incoming_trace_id` return `:cycle`; otherwise recurse with the looked-up node's `parent_step_id` and `hops + 1`; if `:ets.lookup` returns `[]` (orphaned ancestor) return `:no_cycle` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.3.2 In `handle_call({:insert, session_id, node}, ...)`, for any node where `node.parent_step_id != nil` AND the parent is present in ETS: call `detect_cycle(table_name, node.trace_id, node.parent_step_id)` before writing; if `:cycle` is returned, return `{:reply, {:error, :cycle_detected}, state}` immediately with no ETS write and no broadcast; the cycle check must run even when the orphan-promotion path would otherwise apply `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.3.3 In `test/observatory/mesh/causal_dag_test.exs`, write a test `"insert/2 detects cycle A->B->A and returns {:error, :cycle_detected}"` that inserts root node A (trace_id "node-a", parent_step_id nil), inserts node B (trace_id "node-b", parent_step_id "node-a"), then attempts to insert a node with trace_id "node-a" and parent_step_id "node-b", asserting the return value is `{:error, :cycle_detected}` and no new ETS entry was created; write a second test `"insert/2 accepts a clean chain A->B->C without cycle error"` that inserts A, B (parent A), and C (parent B) in order and asserts all three calls return `:ok` `done_when: "mix test test/observatory/mesh/causal_dag_test.exs"`

### 3.1.4 Fork Nodes (Multiple Children)

- [ ] **Task 3.1.4 Complete**
- **Governed by:** ADR-017
- **Parent UCs:** UC-0234

Fork status is derived at read time from the length of a node's `children` list; it is not stored as a flag. `CausalDAG` must update a parent's `children` list atomically each time a new child is attached so that both the first and subsequent children appear in subsequent reads. `TopologyBuilder` uses `children` length > 1 to emit N outgoing edge descriptors for a fork node.

- [ ] 3.1.4.1 Confirm that the `:ets.update_element/3` call used in task 3.1.1.3 to append to a parent's `children` list correctly handles the case where two sequential calls add two different children: the first call sets `children: ["child-X"]`, the second call reads the current list from ETS, appends `"child-Y"`, and writes `children: ["child-X", "child-Y"]` back; implement this as a read-modify-write pattern using `:ets.lookup` + `:ets.insert` wrapped in a GenServer call so no concurrent process can interleave between the read and write `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.4.2 Implement a public `get_children(session_id, trace_id)` function that calls `GenServer.call(__MODULE__, {:get_children, session_id, trace_id})` and returns `{:ok, children_list}` where `children_list` is the `children` field of the node at `trace_id`, or `{:error, :not_found}` if the node does not exist in ETS `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.1.4.3 In `test/observatory/mesh/causal_dag_test.exs`, write a test `"two children with same parent produce a fork node"` that inserts root node A, inserts child X (parent A), inserts child Y (parent A), then calls `CausalDAG.get_children("sess-fork", "node-a")` and asserts the returned list contains both "node-x" and "node-y"; write a second test confirming a node with exactly one child returns a list of length 1 from `get_children/2` `done_when: "mix test test/observatory/mesh/causal_dag_test.exs"`

---

## 3.2 DAG Query API & Pruning

- [ ] **Section 3.2 Complete**

This section exposes the public read API (`get_session_dag/1`), specifies the delta broadcast format and emission rules, and implements session pruning triggered by `is_terminal` signals. Together these four tasks (covering FR-8.5 through FR-8.8) complete the server-side DAG subsystem. All downstream consumers — `TopologyBuilder`, the Session Drill-down LiveView, and the entropy integration test suite — depend on `get_session_dag/1` and the delta broadcast contract being stable before they can be wired.

### 3.2.1 get_session_dag/1

- [ ] **Task 3.2.1 Complete**
- **Governed by:** ADR-017
- **Parent UCs:** UC-0235

`CausalDAG.get_session_dag/1` is the primary read API for both the Session Drill-down LiveView and `TopologyBuilder`. It must return a complete adjacency map of every node currently in ETS for a given session, with `children` lists reflecting all attachments at the moment of the call. For sessions with no ETS table, it must return a structured error rather than raising.

- [ ] 3.2.1.1 Implement `def get_session_dag(session_id)` as a public function that calls `GenServer.call(__MODULE__, {:get_session_dag, session_id})`; implement `handle_call({:get_session_dag, session_id}, _from, state)`: if no entry exists in `:causal_dag_session_registry` for `session_id`, return `{:reply, {:error, :session_not_found}, state}`; otherwise, call `:ets.tab2list(:"dag_#{session_id}")` to read all `{trace_id, node}` tuples, convert to a map `%{trace_id => node}`, and return `{:reply, {:ok, node_map}, state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.2.1.2 In `test/observatory/mesh/causal_dag_test.exs`, write a test `"get_session_dag/1 returns all 12 nodes for a known session"` that inserts 12 nodes across a chain (root + 11 sequential children), calls `CausalDAG.get_session_dag/1`, and asserts `{:ok, map}` is returned where `map_size(map) == 12` and each value is a `%Node{}` struct; write a second test `"get_session_dag/1 returns {:error, :session_not_found} for unknown session"` that calls `get_session_dag("sess-unknown")` on a fresh GenServer and asserts `{:error, :session_not_found}` without raising `done_when: "mix test test/observatory/mesh/causal_dag_test.exs"`

### 3.2.2 DAG Delta Broadcast

- [ ] **Task 3.2.2 Complete**
- **Governed by:** ADR-017
- **Parent UCs:** UC-0236

Every successful node insertion or orphan attachment must produce exactly one PubSub broadcast on `"session:dag:{session_id}"`. The broadcast payload carries `event`, `session_id`, `added_nodes`, `updated_nodes`, and `added_edges` so subscribers can update incrementally. Rejected insertions (cycle detected or missing fields) and unresolved orphan buffer placements must never trigger a broadcast.

- [ ] 3.2.2.1 Implement a private `broadcast_delta(session_id, added_nodes, updated_nodes, added_edges)` function in `Observatory.Mesh.CausalDAG` that calls `Phoenix.PubSub.broadcast(Observatory.PubSub, "session:dag:#{session_id}", %{event: "dag_delta", session_id: session_id, added_nodes: added_nodes, updated_nodes: updated_nodes, added_edges: added_edges})`; ensure this function is called after every successful ETS write (root insert, child attach, and orphan promotion) and never called on `{:error, :cycle_detected}`, `{:error, :missing_fields}`, or buffer placements that have not yet resolved `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.2.2.2 In `test/observatory/mesh/causal_dag_test.exs`, write a test `"successful child insertion broadcasts dag_delta on session:dag topic"` that subscribes the test process to `"session:dag:sess-broadcast"` via `Phoenix.PubSub.subscribe/2`, inserts a root and then a child node, and uses `assert_receive` to confirm a `%{event: "dag_delta", added_nodes: [_], updated_nodes: [_], added_edges: [%{from: _, to: _}]}` message is received; write a second test `"cycle-detected rejection emits no broadcast"` that subscribes the test process to the topic, triggers a cycle-detected rejection, and uses `refute_receive` to assert no message is delivered `done_when: "mix test test/observatory/mesh/causal_dag_test.exs"`

### 3.2.3 ETS Pruning on is_terminal

- [ ] **Task 3.2.3 Complete**
- **Governed by:** ADR-017
- **Parent UCs:** UC-0237

When a session is declared terminal, its ETS table must remain queryable for exactly 5 minutes to allow in-flight drill-down views to complete, then be deleted. A duplicate terminal signal for the same session before the timer fires must be silently ignored — the original scheduled deletion must proceed unchanged.

- [ ] 3.2.3.1 Implement a public `signal_terminal(session_id)` function that calls `GenServer.cast(__MODULE__, {:terminal, session_id})`; implement `handle_cast({:terminal, session_id}, state)`: if `Map.has_key?(state.pending_deletions, session_id)` return `{:noreply, state}` (duplicate — ignore); otherwise, schedule deletion via `timer_ref = Process.send_after(self(), {:prune_session, session_id}, 300_000)`, store `Map.put(state.pending_deletions, session_id, timer_ref)`, and return `{:noreply, updated_state}`; initialize `state` with `pending_deletions: %{}` in `init/1` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.2.3.2 Implement `handle_info({:prune_session, session_id}, state)`: delete the ETS session table via `:ets.delete(:"dag_#{session_id}")`, remove `session_id` from `:causal_dag_session_registry`, remove the `session_id` key from `state.pending_deletions`, and return `{:noreply, updated_state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.2.3.3 In `test/observatory/mesh/causal_dag_test.exs`, write a test `"nodes remain queryable during 5-minute grace window"` that inserts a node, sends `{:terminal, session_id}` via `send/2` directly to the GenServer pid (bypassing the 300_000ms delay by calling `handle_cast` via a test helper that sends the message and immediately sends `{:prune_session, session_id}` after a 0ms `Process.send_after`), then asserts the session is still queryable immediately after signaling terminal; write a second test `"prune_session message deletes ETS table and returns session_not_found"` that sends the prune message directly, then calls `CausalDAG.get_session_dag/1` and asserts `{:error, :session_not_found}`; write a third test `"duplicate terminal signal does not reset the deletion timer"` that calls `signal_terminal/1` twice for the same session and asserts `state.pending_deletions` still contains only one entry for that session_id `done_when: "mix test test/observatory/mesh/causal_dag_test.exs"`

---

## 3.3 Canvas Topology Renderer (JS Hook)

- [ ] **Section 3.3 Complete**

This section creates `assets/js/hooks/topology_map.js`, the `Observatory.Gateway.TopologyBuilder` Elixir module, and establishes the `"gateway:topology"` PubSub broadcast contract. Together these five tasks cover FR-8.9 through FR-8.13 and complete the full data path from ETS DAG to Canvas pixel. No React or D3 dependency is introduced; the Phase 2 migration trigger (>3 interactive requirements needing >200 lines of custom Canvas JS) is explicitly not met at this phase boundary.

### 3.3.1 TopologyMap JS Hook Structure

- [ ] **Task 3.3.1 Complete**
- **Governed by:** ADR-016
- **Parent UCs:** UC-0238

The `TopologyMap` LiveView JS hook must initialize the Canvas 2D context, register for `topology_update` events, attach a click listener, and start the `requestAnimationFrame` animation loop — all without importing any npm package. If the canvas element is absent at mount time, the hook must log an error and abort cleanly without throwing an uncaught exception that would crash the LiveView page.

- [ ] 3.3.1.1 Create `assets/js/hooks/topology_map.js` with `const TopologyMap = { mounted() {}, render() {}, handleClick(e) {}, startAnimationLoop() {} }; export default TopologyMap;` and confirm `mix compile --warnings-as-errors` passes (no Elixir changes, but the assets pipeline must not emit warnings); no `import` or `require` statements are permitted in this file `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.3.1.2 Implement `mounted()`: call `this.canvas = this.el.querySelector('canvas')`; if `this.canvas === null`, log `console.error("TopologyMap: canvas element not found")` and return without further initialization; otherwise call `this.ctx = this.canvas.getContext('2d')`, set `this.nodes = []` and `this.edges = []`, call `this.handleEvent("topology_update", ({nodes, edges}) => { this.nodes = nodes; this.edges = edges; })`, add `this.canvas.addEventListener('click', this.handleClick.bind(this))`, and call `this.startAnimationLoop()` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.3.1.3 Implement `startAnimationLoop()`: assign `this._raf = requestAnimationFrame(() => { this.render(); this.startAnimationLoop(); })`; implement `destroyed()`: call `cancelAnimationFrame(this._raf)` to stop the loop when the LiveView component is removed from the DOM `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.3.1.4 Register `TopologyMap` in `assets/js/app.js` by importing it — `import TopologyMap from "./hooks/topology_map"` — and adding it to the Hooks object passed to the LiveSocket constructor: `const Hooks = { ..., TopologyMap }`; confirm `mix compile --warnings-as-errors` passes after the import is added `done_when: "mix compile --warnings-as-errors"`

### 3.3.2 Node State Color Mapping

- [ ] **Task 3.3.2 Complete**
- **Governed by:** ADR-016
- **Parent UCs:** UC-0239

The Canvas renderer must translate each node's `state` field to an exact hex fill color on every animation frame. The `alert_entropy` state additionally requires a periodic flashing animation on the node's bounding region. Any unrecognised or absent state must fall back to the idle color `#6b7280` without producing a runtime error.

- [ ] 3.3.2.1 In `topology_map.js`, define the color mapping as a module-level constant `const NODE_COLORS = { idle: "#6b7280", active: "#3b82f6", alert_entropy: "#ef4444", schema_violation: "#f97316", dead: "#374151", blocked: "#f59e0b" };` immediately after the closing brace of the TopologyMap object definition; add a comment `// Colors match ADR-016: idle=#6b7280, active=#3b82f6, alert_entropy=#ef4444, schema_violation=#f97316, dead=#374151, blocked=#f59e0b` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.3.2.2 Implement `render()` in `TopologyMap`: clear the canvas with `this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)`; iterate `this.nodes` and for each node: resolve the fill color as `NODE_COLORS[node.state] || NODE_COLORS.idle`; set `this.ctx.fillStyle = color`; draw a filled circle with `this.ctx.arc(node.x || 0, node.y || 0, 12, 0, Math.PI * 2)`; for `alert_entropy` nodes, apply a flashing effect by modulating `this.ctx.globalAlpha` using `0.5 + 0.5 * Math.sin(Date.now() / 300)` before drawing, then restoring `globalAlpha` to `1.0` afterward; after drawing nodes, iterate `this.edges` and draw each as a line from `{from_x, from_y}` to `{to_x, to_y}` `done_when: "mix compile --warnings-as-errors"`

### 3.3.3 Edge Click pushEvent Contract

- [ ] **Task 3.3.3 Complete**
- **Governed by:** ADR-016
- **Parent UCs:** UC-0240

`handleClick(e)` must translate a canvas mouse event into either an `edge_selected` pushEvent (when the click lands within pixel-width tolerance of an edge line), a `node_selected` pushEvent (when the click lands within a node bounding circle), or no action (when the click lands on empty space). Node hit detection takes precedence over edge detection when coordinates could match both.

- [ ] 3.3.3.1 Implement `handleClick(e)` in `TopologyMap`: compute canvas-local coordinates via `const rect = this.canvas.getBoundingClientRect(); const x = e.clientX - rect.left; const y = e.clientY - rect.top;`; define `const HIT_RADIUS = 14` for node bounding circles and `const EDGE_TOLERANCE = 6` for edge line proximity; first test all nodes — if `Math.hypot(x - node.x, y - node.y) <= HIT_RADIUS` for any node, call `this.pushEvent("node_selected", { trace_id: node.trace_id })` and return immediately `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.3.3.2 After the node check returns without a match, test all edges — for each edge, compute the point-to-segment distance from `(x, y)` to the line segment from `(edge.from_x, edge.from_y)` to `(edge.to_x, edge.to_y)` using the standard perpendicular distance formula; if the distance is `<= EDGE_TOLERANCE`, call `this.pushEvent("edge_selected", { traffic_volume: edge.traffic_volume || 0, latency_ms: edge.latency_ms || 0, status: edge.status || "unknown" })` and return; if neither nodes nor edges match, return without calling pushEvent `done_when: "mix compile --warnings-as-errors"`

### 3.3.4 TopologyBuilder Module

- [ ] **Task 3.3.4 Complete**
- **Governed by:** ADR-016, ADR-017
- **Parent UCs:** UC-0241

`Observatory.Gateway.TopologyBuilder` subscribes to `"session:dag:{session_id}"` delta events, reads the full adjacency map from `CausalDAG.get_session_dag/1` for the affected session, derives node and edge descriptor lists, and broadcasts to `"gateway:topology"`. It must not maintain its own copy of DAG node data. When `CausalDAG.get_session_dag/1` returns `{:error, :session_not_found}` for a pruned session, `TopologyBuilder` must skip that session silently without crashing.

- [ ] 3.3.4.1 Create `lib/observatory/gateway/topology_builder.ex` with `use GenServer`; in `init/1`, subscribe to `Phoenix.PubSub` topic `"session:dag:*"` is not directly possible — instead, subscribe to a registry topic `"dag:updates"` where `CausalDAG` broadcasts a meta-event `{:session_dag_updated, session_id}` after each delta; implement `handle_info({:session_dag_updated, session_id}, state)` that calls `CausalDAG.get_session_dag(session_id)` and pattern-matches on the result `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.3.4.2 On `{:ok, node_map}` result from `get_session_dag/1`: derive `nodes` list — map each `%Node{}` to `%{trace_id: n.trace_id, agent_id: n.agent_id, state: n.action_status || :idle, x: nil, y: nil}`; derive `edges` list — for each node that has non-empty `children`, emit one edge descriptor `%{from: n.trace_id, to: child_id, traffic_volume: 0, latency_ms: 0, status: "active", from_x: nil, from_y: nil, to_x: nil, to_y: nil}` per child entry; broadcast `%{nodes: nodes, edges: edges}` to `"gateway:topology"` via `Phoenix.PubSub.broadcast/3`; on `{:error, :session_not_found}`, log a debug message and return `{:noreply, state}` without broadcasting `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.3.4.3 Update `CausalDAG`'s `broadcast_delta/4` to also publish `{:session_dag_updated, session_id}` to the `"dag:updates"` meta-topic after every successful delta broadcast, so `TopologyBuilder` is notified; alternatively, have `TopologyBuilder` subscribe directly to each `"session:dag:{session_id}"` topic by implementing a `subscribe_to_session(session_id)` call triggered by a `{:new_session, session_id}` registry event `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.3.4.4 Create `test/observatory/gateway/topology_builder_test.exs`; write a test `"TopologyBuilder broadcasts to gateway:topology after DAG delta"` that subscribes the test process to `"gateway:topology"`, inserts a 3-node chain into `CausalDAG`, and asserts `assert_receive %{nodes: nodes, edges: edges}` where `length(nodes) == 3` and `length(edges) == 2`; write a second test `"TopologyBuilder skips pruned session silently"` that mocks or stubs `CausalDAG.get_session_dag/1` to return `{:error, :session_not_found}` and asserts `TopologyBuilder` does not crash and no broadcast is received on `"gateway:topology"` `done_when: "mix test test/observatory/gateway/topology_builder_test.exs"`

### 3.3.5 gateway:topology PubSub Topic

- [ ] **Task 3.3.5 Complete**
- **Governed by:** ADR-016
- **Parent UCs:** UC-0249

`"gateway:topology"` is the sole channel through which the Fleet Command LiveView learns of node and edge state changes. The Fleet Command LiveView must subscribe to this topic in `mount/3` and forward each broadcast payload to the `TopologyMap` hook via `push_event/3`. Direct ETS reads from the LiveView are explicitly prohibited.

- [ ] 3.3.5.1 In the Fleet Command LiveView module (to be created in Phase 5, but the subscription contract must be documented and test-verified here), write a test in `test/observatory/gateway/topology_builder_test.exs` that broadcasts a test message directly to `"gateway:topology"` and asserts a subscriber process (simulating the LiveView's `handle_info`) receives a message with `nodes` and `edges` keys; this test validates the topic contract before the LiveView module exists `done_when: "mix test test/observatory/gateway/topology_builder_test.exs"`
- [ ] 3.3.5.2 Add a moduledoc comment to `lib/observatory/gateway/topology_builder.ex` stating: `@moduledoc "Sole publisher on the \\"gateway:topology\\" PubSub topic. Fleet Command LiveView subscribes to this topic in mount/3. Direct ETS reads from LiveView are prohibited (FR-8.13, ADR-016)."` and confirm `mix compile --warnings-as-errors` passes with the moduledoc `done_when: "mix compile --warnings-as-errors"`

---

## 3.4 EntropyTracker Sliding Window

- [ ] **Section 3.4 Complete**

This section creates the `Observatory.Gateway.EntropyTracker` GenServer, establishes its private ETS sliding window data structure, and implements the `record_and_score/2` entry point including window eviction and the uniqueness ratio computation. These tasks cover FR-9.1 through FR-9.3 and must be complete before any severity classification, alerting, or `SchemaInterceptor` integration can be tested in isolation.

### 3.4.1 EntropyTracker GenServer & ETS

- [ ] **Task 3.4.1 Complete**
- **Governed by:** ADR-018
- **Parent UCs:** UC-0242, UC-0250

`EntropyTracker` is the single authoritative owner of per-session sliding window data. No other module may write entropy tuples directly to ETS; the table is declared with access `:private` so the OTP runtime enforces this at the process boundary. The public API is `record_and_score/2`, called synchronously by `SchemaInterceptor`.

- [ ] 3.4.1.1 Create `lib/observatory/gateway/entropy_tracker.ex` with `use GenServer`; in `init/1`, create a private ETS table via `:ets.new(:entropy_windows, [:set, :private, {:heir, :none, nil}])` and store the table reference in the GenServer state map as `%{table: table_ref}`; implement `start_link/1` and register the process under the module name `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.4.1.2 Implement the public API: `def record_and_score(session_id, {intent, tool_call, action_status})` calls `GenServer.call(__MODULE__, {:record_and_score, session_id, {intent, tool_call, action_status}})`; the call is synchronous — no `Task.async`, no `cast`; the return type is `{:ok, score, severity}` or `{:error, :missing_agent_id}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.4.1.3 In `test/observatory/gateway/entropy_tracker_test.exs` (create this file with `use ExUnit.Case, async: false`), write a test `"ETS table is private and inaccessible from outside the GenServer process"` that starts `EntropyTracker` via `start_supervised!`, then in the test process attempts `:ets.lookup(:entropy_windows, "any-session")` and asserts it raises `ArgumentError` (ETS `:private` tables reject lookups from non-owner processes) `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`

### 3.4.2 Sliding Window Mechanics

- [ ] **Task 3.4.2 Complete**
- **Governed by:** ADR-018
- **Parent UCs:** UC-0250

The window for each session must hold the last N tuples in insertion order (N read from `Application.get_env(:observatory, :entropy_window_size, 5)` on each call). When a new tuple arrives and the window is at capacity, the oldest tuple is evicted from the head. When fewer than N tuples have been received, the uniqueness ratio is computed over the available entries.

- [ ] 3.4.2.1 Implement `handle_call({:record_and_score, session_id, tuple}, _from, %{table: table} = state)`: read the current window from ETS via `:ets.lookup(table, session_id)` — if no entry exists, the window is `[]`; read `window_size = Application.get_env(:observatory, :entropy_window_size, 5)` on this call; append the new tuple to the window; if `length(updated_window) > window_size`, drop the first element via `List.delete_at(updated_window, 0)` to evict the oldest; write the updated window back to ETS via `:ets.insert(table, {session_id, updated_window})` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.4.2.2 In `test/observatory/gateway/entropy_tracker_test.exs`, write a test `"sixth tuple evicts oldest and window remains capped at 5"` that calls `record_and_score/2` six times with six distinct tuples for the same session and asserts the function returns `{:ok, _, _}` on each call; then (by accessing state via a test-only `:get_window` call on the GenServer, or by designing `record_and_score` to return the window size as additional info in test mode) assert the window contains exactly 5 tuples and the first (oldest) tuple is not present; write a second test `"score computed over 3 tuples equals unique_count divided by 3"` that inserts 3 distinct tuples and asserts the returned score equals `1.0` (3 unique / 3 total) rounded to 4 decimal places `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`

---

## 3.5 Entropy Alerting & Severity

- [ ] **Section 3.5 Complete**

This section implements the uniqueness ratio computation and all three severity classification paths — LOOP (score < 0.25), WARNING (0.25 <= score < 0.50), and Normal (score >= 0.50) — along with their associated PubSub broadcasts and the `EntropyAlertEvent` construction and field-validation logic. These tasks cover FR-9.3 through FR-9.7 and must complete before the `SchemaInterceptor` integration in section 3.6 can be tested end-to-end.

### 3.5.1 Uniqueness Ratio Computation

- [ ] **Task 3.5.1 Complete**
- **Governed by:** ADR-018
- **Parent UCs:** UC-0243

The entropy score is `unique_count / window_size` using exact tuple equality, rounded to 4 decimal places. Computation is synchronous and occurs within the same process call as `record_and_score/2`. For partial windows (fewer than the configured maximum entries), the ratio is computed over the available N entries.

- [ ] 3.5.1.1 Implement a private `compute_score(window)` function in `EntropyTracker`: `n = length(window)`; if `n == 0` return `1.0` (empty window treated as fully unique — no loop possible); `unique = window |> MapSet.new() |> MapSet.size()`; compute `Float.round(unique / n, 4)` and return the result; this function is called synchronously inside `handle_call({:record_and_score, ...})` after the window has been updated `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.5.1.2 In `test/observatory/gateway/entropy_tracker_test.exs`, write the following unit tests directly against `compute_score` (make it accessible via `@doc false` or by testing via `record_and_score` return values): `"5 identical tuples yield score 0.2"` — inserts same tuple 5 times, asserts `{:ok, 0.2, :loop}`; `"5 unique tuples yield score 1.0"` — inserts 5 distinct tuples, asserts `{:ok, 1.0, :normal}`; `"3 tuples with 2 unique yield score 0.6667"` — inserts 3 tuples where 2 are identical and 1 is distinct, asserts the score field equals `0.6667` `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`

### 3.5.2 LOOP Threshold Actions (score < 0.25)

- [ ] **Task 3.5.2 Complete**
- **Governed by:** ADR-018, ADR-021
- **Parent UCs:** UC-0251

When the computed score is strictly less than the LOOP threshold (read from `Application.get_env(:observatory, :entropy_loop_threshold, 0.25)` on every call), `EntropyTracker` must perform three actions atomically within the same `record_and_score/2` call: broadcast an `EntropyAlertEvent` to `"gateway:entropy_alerts"`, broadcast a topology state update with `state: "alert_entropy"` to `"gateway:topology"`, and return `{:ok, score, :loop}`. A score exactly equal to 0.25 must not trigger LOOP severity.

- [ ] 3.5.2.1 After `compute_score/1` returns inside `handle_call({:record_and_score, session_id, _tuple}, ...)`: read `loop_threshold = Application.get_env(:observatory, :entropy_loop_threshold, 0.25)` — validate it is a number via `is_number/1`; if not a number, log `Logger.warning("EntropyTracker: invalid entropy_loop_threshold value #{inspect(loop_threshold)}, using default 0.25")` and set `loop_threshold = 0.25`; if `score < loop_threshold`, attempt to build and broadcast `EntropyAlertEvent` (see 3.5.5), broadcast `Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:topology", %{session_id: session_id, state: "alert_entropy"})`, and return `{:reply, {:ok, score, :loop}, state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.5.2.2 In `test/observatory/gateway/entropy_tracker_test.exs`, write a test `"score 0.2 triggers LOOP: returns {:ok, 0.2, :loop} and broadcasts to both topics"` that subscribes the test process to `"gateway:entropy_alerts"` and `"gateway:topology"`, seeds the session with 5 identical tuples and an `agent_id` stored in session state, calls `record_and_score/2`, asserts the return value is `{:ok, 0.2, :loop}`, then uses `assert_receive` to confirm a message arrives on both PubSub topics; write a second test `"score exactly 0.25 does NOT trigger LOOP"` that arranges the window to produce a score of `0.25`, calls `record_and_score/2`, asserts the return value does not match `{:ok, _, :loop}`, and uses `refute_receive` to confirm no message is delivered to `"gateway:entropy_alerts"` `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`

### 3.5.3 WARNING Range (0.25 <= score < 0.50)

- [ ] **Task 3.5.3 Complete**
- **Governed by:** ADR-018
- **Parent UCs:** UC-0244, UC-0252

When the score is within the WARNING band (>= LOOP threshold and < WARNING threshold), `EntropyTracker` must broadcast a topology update setting the node to `:blocked` (amber) state and return `{:ok, score, :warning}`. No `EntropyAlertEvent` is emitted for WARNING severity. The WARNING threshold is read from `Application.get_env(:observatory, :entropy_warning_threshold, 0.50)` on each call. A prior WARNING state must not suppress a subsequent LOOP classification on the next call.

- [ ] 3.5.3.1 In the severity evaluation chain inside `handle_call({:record_and_score, ...})`: after the LOOP check fails, read `warning_threshold = Application.get_env(:observatory, :entropy_warning_threshold, 0.50)` — validate it is a number; if not, log a warning and use `0.50`; if `score < warning_threshold` (i.e., LOOP threshold <= score < WARNING threshold): broadcast `Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:topology", %{session_id: session_id, state: "blocked"})`; do NOT broadcast to `"gateway:entropy_alerts"`; update the session's stored severity in ETS to `:warning`; return `{:reply, {:ok, score, :warning}, state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.5.3.2 In `test/observatory/gateway/entropy_tracker_test.exs`, write a test `"score 0.4 triggers WARNING: returns {:ok, 0.4, :warning} with topology broadcast but no alert"` that subscribes the test process to both topics, arranges the window to produce `score = 0.4`, calls `record_and_score/2`, asserts `{:ok, 0.4, :warning}`, then uses `assert_receive` to confirm a `"gateway:topology"` message with `state: "blocked"` arrives, and uses `refute_receive` to confirm no message arrives on `"gateway:entropy_alerts"`; write a second test `"prior WARNING does not suppress LOOP escalation"` that first drives a session to WARNING (score 0.4), then drives it to LOOP (score 0.2), and asserts the second call returns `{:ok, 0.2, :loop}` and broadcasts to `"gateway:entropy_alerts"` `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`

### 3.5.4 Normal Range Recovery (score >= 0.50)

- [ ] **Task 3.5.4 Complete**
- **Governed by:** ADR-018
- **Parent UCs:** UC-0252

When the score meets or exceeds the WARNING threshold, the session is classified as Normal. No alert is emitted. If the session was previously in WARNING or LOOP state (tracked in ETS alongside the sliding window), `EntropyTracker` must broadcast a topology update resetting the node to `:active` to clear the visual alert indicator. A score of exactly `0.50` is Normal, not WARNING.

- [ ] 3.5.4.1 Store each session's prior severity alongside its window in ETS as a tuple `{window, prior_severity}` where `prior_severity` is `:normal`, `:warning`, or `:loop`; on each call, read the prior severity before updating; in the Normal classification path (score >= warning_threshold): if `prior_severity in [:warning, :loop]`, broadcast `Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:topology", %{session_id: session_id, state: "active"})` to reset the visual state; write the updated ETS entry with `prior_severity: :normal`; return `{:reply, {:ok, score, :normal}, state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.5.4.2 In `test/observatory/gateway/entropy_tracker_test.exs`, write a test `"score 0.8 returns {:ok, 0.8, :normal} with no alert broadcast"` that subscribes the test process to both topics, seeds a healthy session (5 distinct tuples), calls `record_and_score/2`, asserts `{:ok, 1.0, :normal}` (5 unique / 5 total), and uses `refute_receive` to confirm no messages arrive on either topic; write a second test `"score recovering from LOOP to 0.8 broadcasts :active reset to gateway:topology"` that first drives the session to LOOP (score 0.2), then adds 4 distinct tuples to bring the score to Normal, calls `record_and_score/2`, and uses `assert_receive` to confirm a topology message with `state: "active"` is received; write a third test confirming `{:ok, 0.5, :normal}` is returned when the score is exactly `0.50` `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`

### 3.5.5 EntropyAlertEvent Fields

- [ ] **Task 3.5.5 Complete**
- **Governed by:** ADR-018
- **Parent UCs:** UC-0245

Every `EntropyAlertEvent` broadcast to `"gateway:entropy_alerts"` must contain all seven required fields: `event_type`, `session_id`, `agent_id`, `entropy_score`, `window_size`, `repeated_pattern`, and `occurrence_count`. If `agent_id` is not available for the session, the event must not be broadcast and `record_and_score/2` must return `{:error, :missing_agent_id}`.

- [ ] 3.5.5.1 Extend the ETS window entry to a tuple `{window, prior_severity, agent_id}` where `agent_id` is initially `nil` and is set when `record_and_score/2` is called with a session that carries agent_id context; add a second public function `register_agent(session_id, agent_id)` that calls `GenServer.cast(__MODULE__, {:register_agent, session_id, agent_id})` to store the `agent_id` for a session before or after the first `record_and_score/2` call; alternatively, extend the `record_and_score/2` call to accept a 3-tuple `{session_id, tuple, agent_id}` and always require the caller to provide `agent_id` — choose the approach consistent with the `SchemaInterceptor` call contract in UC-0253 `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.5.5.2 Implement a private `build_alert_event(session_id, agent_id, score, window)` function that: if `agent_id == nil`, logs `Logger.warning("EntropyTracker: cannot emit alert, missing agent_id for session #{session_id}")` and returns `{:error, :missing_agent_id}`; otherwise, compute `repeated_pattern` as the most frequently occurring tuple in `window` using `Enum.frequencies/1` + `Enum.max_by/2`; compute `occurrence_count` as the frequency of that tuple; build the event map `%{event_type: "entropy_alert", session_id: session_id, agent_id: agent_id, entropy_score: score, window_size: length(window), repeated_pattern: %{intent: elem(pattern, 0), tool_call: elem(pattern, 1), action_status: to_string(elem(pattern, 2))}, occurrence_count: count}`; broadcast via `Phoenix.PubSub.broadcast/3` and return `:ok` `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.5.5.3 In `test/observatory/gateway/entropy_tracker_test.exs`, write a test `"EntropyAlertEvent contains all 7 required fields with correct values"` that registers a known `agent_id` for a session, seeds the window with 5 tuples where 4 are `{:search, "list_files", :failure}` and 1 is distinct, triggers LOOP severity, subscribes the test process to `"gateway:entropy_alerts"`, calls `record_and_score/2`, and uses `assert_receive %{event_type: "entropy_alert", session_id: _, agent_id: "agent-7", entropy_score: 0.4, window_size: 5, repeated_pattern: %{intent: "search", tool_call: "list_files", action_status: "failure"}, occurrence_count: 4}`; write a second test `"missing agent_id returns {:error, :missing_agent_id} and no alert broadcast"` that calls `record_and_score/2` for a session with no registered `agent_id` producing a LOOP score, asserts the return is `{:error, :missing_agent_id}`, and uses `refute_receive` to confirm no message arrives on `"gateway:entropy_alerts"` `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`

---

## 3.6 Entropy PubSub & SchemaInterceptor Integration

- [ ] **Section 3.6 Complete**

This section wires `EntropyTracker` into the `SchemaInterceptor` pipeline established in Phase 2, implements the Gateway-authoritative score overwrite on the `DecisionLog` envelope, configures the Session Cluster Manager LiveView's `"gateway:entropy_alerts"` subscription and deduplication logic, and verifies that all three `Application.get_env` configuration reads occur per-call with correct fallback behavior. These tasks cover FR-9.8 through FR-9.11 and represent the final integration seam that makes the entire topology and entropy system observable end-to-end.

### 3.6.1 Gateway Authoritative Score Overwrite

- [ ] **Task 3.6.1 Complete**
- **Governed by:** ADR-018, ADR-015
- **Parent UCs:** UC-0246

`SchemaInterceptor` must call `EntropyTracker.record_and_score/2` synchronously after each successful schema validation and use the returned score to overwrite `cognition.entropy_score` in the outbound `DecisionLog` envelope via `DecisionLog.put_gateway_entropy_score/2`. If `record_and_score/2` returns an error, the original agent-reported score is retained and a `schema_violation` log entry is emitted.

- [ ] 3.6.1.1 In `lib/observatory/gateway/schema_interceptor.ex` (created in Phase 2), locate the post-validation routing function (the function that broadcasts a validated `DecisionLog` to downstream subscribers); add a call to `EntropyTracker.record_and_score(session_id, {intent, tool_call, action_status})` synchronously BEFORE the broadcast — not wrapped in `Task.async`, not cast; extract `session_id`, `intent`, `tool_call`, and `action_status` from the validated `%DecisionLog{}` struct using pattern matching on the embedded sub-schemas `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.6.1.2 Pattern-match on the result: on `{:ok, score, _severity}`, call `updated_log = DecisionLog.put_gateway_entropy_score(log, score)` and broadcast `updated_log`; on `{:error, :missing_agent_id}`, log `Logger.warning("SchemaInterceptor: entropy computation failed for session #{session_id}, retaining agent-reported score")`, emit a `SchemaViolationEvent` (or equivalent log structure from Phase 2) noting the failed entropy computation, and broadcast the original `log` with the agent-reported score unchanged `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.6.1.3 In `test/observatory/gateway/entropy_tracker_test.exs`, write an integration test `"SchemaInterceptor overwrites cognition.entropy_score with Gateway-computed value"` that processes a valid `DecisionLog` with `cognition.entropy_score: 0.9` through `SchemaInterceptor`, subscribes the test process to the downstream broadcast topic, triggers the pipeline, and asserts the received `DecisionLog` has `cognition.entropy_score != 0.9` and equals the value that `EntropyTracker` would compute for that session; write a second test `"SchemaInterceptor retains original score when EntropyTracker returns error"` that arranges for `record_and_score/2` to return `{:error, :missing_agent_id}` (by not registering an agent_id) and asserts the outbound log retains `cognition.entropy_score: 0.9` `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`

### 3.6.2 SchemaInterceptor Call Contract

- [ ] **Task 3.6.2 Complete**
- **Governed by:** ADR-018, ADR-015
- **Parent UCs:** UC-0253

`EntropyTracker.record_and_score/2` must only be called after successful schema validation. Messages that fail validation must not update the sliding window. The call is synchronous — no `Task.async` or cast dispatch.

- [ ] 3.6.2.1 Confirm in the `SchemaInterceptor` implementation (from Phase 2) that the `validate/1` function returns either `{:ok, log}` or `{:error, violation}` and that `record_and_score/2` is called only inside the `{:ok, log}` branch; add an ExUnit test in `test/observatory/gateway/schema_interceptor_test.exs` that processes a schema-invalid message (missing required field `identity.agent_id`) and asserts `EntropyTracker.record_and_score/2` was not called (verified by checking the session window size remains 0 via a subsequent call with a fresh valid message and asserting `window_size == 1`) `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs"`
- [ ] 3.6.2.2 Add a code comment in `lib/observatory/gateway/schema_interceptor.ex` at the `record_and_score/2` call site: `# Synchronous call per FR-9.9 and ADR-018. Must NOT be Task.async or GenServer.cast.` and confirm `mix compile --warnings-as-errors` passes `done_when: "mix compile --warnings-as-errors"`

### 3.6.3 gateway:entropy_alerts PubSub & Deduplication

- [ ] **Task 3.6.3 Complete**
- **Governed by:** ADR-018
- **Parent UCs:** UC-0247

The Session Cluster Manager LiveView must subscribe to `"gateway:entropy_alerts"` in `mount/3` and render each affected session in an Entropy Alerts panel with a "Pause and Inspect" button. Duplicate `EntropyAlertEvent` messages for the same `session_id` must be deduplicated: the session may appear in the panel only once regardless of how many alerts are received. Clicking "Pause and Inspect" must issue a Pause command to the HITL API for the affected `session_id`. No other UI component may subscribe to `"gateway:entropy_alerts"` in Phase 1.

- [ ] 3.6.3.1 In the Session Cluster Manager LiveView module (to be fully implemented in Phase 5, but the subscription and deduplication contract must be specified here as implementation tasks): implement `mount/3` to include `Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:entropy_alerts")`; implement `handle_info(%{event_type: "entropy_alert", session_id: sid} = event, socket)` that checks `socket.assigns.entropy_alerts` (a map keyed by `session_id`) — if `sid` is already present, update only the `entropy_score` field of the existing entry; if `sid` is absent, add a new entry; assign the updated map back to the socket `done_when: "mix compile --warnings-as-errors"`
- [ ] 3.6.3.2 In `test/observatory/gateway/entropy_tracker_test.exs`, write a test `"two EntropyAlertEvents for same session_id appear only once in alerts map"` using a simple map-deduplication unit test: call the deduplication logic (extracted as a pure function or tested via the LiveView's `handle_info` in a ConnCase test) with two events for the same `session_id` and assert the resulting map has size 1 with the `session_id` as key; write a second test `"EntropyAlertEvents for two different sessions produce two map entries"` that processes two events with different `session_ids` and asserts the resulting map has size 2 `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`

### 3.6.4 Runtime Configuration of Thresholds

- [ ] **Task 3.6.4 Complete**
- **Governed by:** ADR-018
- **Parent UCs:** UC-0248

All three `EntropyTracker` configuration values — `entropy_window_size`, `entropy_loop_threshold`, and `entropy_warning_threshold` — must be read via `Application.get_env` on every `record_and_score/2` call, not cached at startup. Invalid type values must log a warning and fall back to the documented defaults without crashing the process.

- [ ] 3.6.4.1 Verify that all three `Application.get_env` calls are inside `handle_call({:record_and_score, ...})` and not in `init/1` or a module attribute; add ExUnit tests in `test/observatory/gateway/entropy_tracker_test.exs` for each config key: `"runtime change to entropy_loop_threshold takes effect on next record_and_score call"` — `Application.put_env(:observatory, :entropy_loop_threshold, 0.30)`, then call `record_and_score/2` with a window that yields `0.28`, assert `{:ok, 0.28, :loop}`; clean up with `Application.delete_env(:observatory, :entropy_loop_threshold)` in an `on_exit` callback `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`
- [ ] 3.6.4.2 Write a test `"invalid string value for entropy_loop_threshold falls back to default 0.25"` that calls `Application.put_env(:observatory, :entropy_loop_threshold, "bad")`, then calls `record_and_score/2` with a window that produces `0.20` (which is LOOP under the default 0.25 but would also be LOOP under the bogus "bad" threshold after fallback), asserts `{:ok, 0.20, :loop}` is returned, and uses `assert_receive` via Logger metadata that a warning was logged containing the invalid value (or use `ExUnit.CaptureLog` to assert the warning log message contains `"invalid entropy_loop_threshold"`); clean up with `Application.delete_env` in `on_exit` `done_when: "mix test test/observatory/gateway/entropy_tracker_test.exs"`
- [ ] 3.6.4.3 Run the full build to confirm zero warnings: `mix compile --warnings-as-errors && mix test test/observatory/mesh/causal_dag_test.exs test/observatory/gateway/entropy_tracker_test.exs test/observatory/gateway/topology_builder_test.exs test/observatory/gateway/schema_interceptor_test.exs` and verify all tests pass with no compiler warnings `done_when: "mix compile --warnings-as-errors && mix test test/observatory/mesh/causal_dag_test.exs test/observatory/gateway/entropy_tracker_test.exs test/observatory/gateway/topology_builder_test.exs"`
