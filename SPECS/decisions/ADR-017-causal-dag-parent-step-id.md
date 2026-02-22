---
id: ADR-017
title: Causal DAG via parent_step_id
date: 2026-02-21
status: proposed
related_tasks: []
parent: ADR-014
superseded_by: null
---
# ADR-017 Causal DAG via parent_step_id
[2026-02-21] proposed

## Related ADRs
- [ADR-014](ADR-014-decision-log-envelope.md) DecisionLog Universal Message Envelope (parent)
- [ADR-016](ADR-016-canvas-topology-renderer.md) Canvas-Based Topology Map Renderer
- [ADR-022](ADR-022-six-view-ui-architecture.md) Six-View UI Information Architecture

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief §4.3, §4.4 | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | Topology Map causal graphing and Session Drill-down DAG |

## Context

Two UI features require reconstructing the causal chain of agent decisions:

1. **Topology Map edges** — lines connecting nodes. A line from A to B means: B's action was caused by a message from A. Without a parent reference, edges must be inferred from timing, which is ambiguous when agents interleave.

2. **Session Drill-down DAG** — directed acyclic graph of a single session's logic. Each node is one DecisionLog step. Edges trace the "because of" relationship.

The `meta.parent_step_id` field in the DecisionLog schema (ADR-014) is the structural primitive for both. The question is how the Gateway reconstructs the graph from a stream of messages, and how it handles common edge cases.

## Options Considered

1. **Client-side DAG construction** — UI receives raw DecisionLog stream and builds the graph in JavaScript. Gateway does no graph work.
   - Pro: Simple Gateway. UI has full data for layout decisions.
   - Con: UI must buffer out-of-order messages. Race conditions when messages arrive faster than rendering. UI complexity high.

2. **Gateway-side DAG construction + push** — `Observatory.Gateway.TopologyBuilder` maintains an in-memory DAG (ETS-backed). On each new message, updates the DAG and broadcasts the delta to subscribers.
   - Pro: Single authoritative DAG. Out-of-order messages handled at Gateway with buffering. UI receives pre-computed graph deltas.
   - Con: Gateway holds session state (DAG per session). Memory pressure for long sessions.

3. **Hybrid: Gateway maintains adjacency list, UI builds layout** — Gateway tracks `{trace_id → parent_step_id}` mappings (minimal state). UI queries adjacency list on demand for layout.
   - Pro: Minimal Gateway state. UI controls layout algorithm.
   - Con: UI must handle adjacency list queries; increases UI-Gateway coupling.

## Decision

**Option 2** — Gateway-side DAG construction with ETS-backed adjacency maps per session.

**Data model:**

```elixir
# lib/observatory/mesh/causal_dag.ex
# ETS table per session: {session_id, trace_id} → %Node{
#   trace_id: string,
#   parent_step_id: string | nil,
#   agent_id: string,
#   intent: string,
#   confidence_score: float,
#   entropy_score: float,
#   action_status: atom,
#   timestamp: datetime,
#   children: [trace_id]
# }
```

**Out-of-order handling:** A message with `parent_step_id` pointing to a `trace_id` not yet in the DAG is held in a 30-second buffer. If the parent arrives within 30s, the child is attached retroactively and a delta is broadcast. If the parent never arrives, the orphan node is attached to the session root with a warning flag.

**Graph properties enforced:**
- No cycles — a `trace_id` cannot appear as its own ancestor (validated at insert)
- Root nodes — `parent_step_id == nil` creates a root; each session may have multiple roots (parallel initial triggers)
- Fork rendering — a node with N children is a "fork node"; topology map renders 1→N edge from parent

**Topology map broadcasts:**
```json
{
  "event": "dag_delta",
  "session_id": "...",
  "added_nodes": [...],
  "updated_nodes": [...],
  "added_edges": [{"from": "uuid-A", "to": "uuid-B"}]
}
```

**Session Drill-down:** Requests full DAG for a `session_id`. `CausalDAG.get_session_dag/1` returns the full adjacency map. UI renders it once, then receives incremental deltas via PubSub.

## Rationale

Gateway-side construction is necessary because the UI (Phoenix LiveView) cannot efficiently maintain per-session graph state across multiple subscribers. If three operators have the same session open in the drill-down, they all need the same graph — building it three times in three browsers wastes compute. The Gateway builds it once; all subscribers receive the same delta stream.

The 30-second orphan buffer handles the common case where agent B's message arrives before agent A's (the parent) due to network jitter. The timeout prevents unbounded buffer growth.

## Consequences

- New module: `lib/observatory/mesh/causal_dag.ex` (ETS-backed DAG with insert, query, delta broadcast)
- ETS table per active session — pruned on session terminal signal (`control.is_terminal == true`)
- New PubSub topic: `"session:dag:{session_id}"` — delta broadcasts for Drill-down subscribers
- `TopologyBuilder` (ADR-016) reads from CausalDAG for node/edge rendering
- Memory bound: N active sessions × average session depth × node struct size (~500 bytes each)
- Session clean-up: CausalDAG prunes ETS table 5 minutes after session terminal signal
