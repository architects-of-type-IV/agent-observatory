# ARCHITECTS IV HYPERVISOR OBSERVATORY
## Project Brief: Hypervisor for Machine Cognition

**Version:** 1.0
**Date:** 2026-02-21
**Status:** Approved for ADR Extraction
**Supersedes:** None (greenfield evolution of Observatory)

---

## 1. Vision

Observatory evolves from a passive monitoring dashboard into a **Hypervisor for Machine Cognition** — a real-time control plane that manages, traces, and intervenes in autonomous AI agent meshes at arbitrary scale.

Where Observatory watches, the Hypervisor governs. The distinction is causal: the Hypervisor can explain *why* an agent took an action, interrupt it before harm occurs, re-route work when a node fails, and audit the exact chain of decisions that led to an outcome.

---

## 2. Problem Statement

Existing agent observability tools treat agents as black boxes. Operators can see *that* an agent ran a tool, but not *why* — what reasoning led to that tool call, how confident the agent was, or whether it was looping. At mesh scale (dozens to hundreds of parallel agents), this opacity creates four systemic risks:

1. **State drift** — Agents develop divergent mental models of shared state. No mechanism exists to detect or reconcile divergence before it cascades.
2. **Cascading failures** — A single bad agent decision propagates through downstream agents before any human can intervene.
3. **Hallucination propagation** — An agent commits a fabricated fact to shared memory; downstream agents consume it as ground truth. The infection timestamp and source are undetectable after the fact.
4. **Budget blindness** — Cost accumulates across a mesh silently. No per-branch or per-session heatmap tells the operator where resources are burning.

The Hypervisor addresses all four risks through a structured approach: enforce a canonical message envelope (DecisionLog), validate it at a Gateway boundary, and make its contents queryable from a real-time UI.

---

## 3. System Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   Agent Mesh                         │
│  [Agent A]  [Agent B]  [Agent C]  [Agent D] ...     │
│       │           │          │          │            │
└───────┴───────────┴──────────┴──────────┴───────────┘
                         │
              DecisionLog messages
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│                  The Gateway                         │
│  - Schema Interceptor (validate / reject / log)      │
│  - Event Bus (NATS or PubSub)                        │
│  - Capability Map (agent registry, heartbeats)       │
│  - Cron Scheduler (leader election, DLQ)             │
│  - Webhook Router (inbound/outbound, retry)          │
│  - HITL Command Relay (Pause/Rewrite/Inject)         │
└─────────────────────────────────────────────────────┘
                         │
              Real-time event stream
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│                   The UI                             │
│  1. Fleet Command (Topology Map + Health)            │
│  2. Session Cluster Manager (DAG + HITL Console)     │
│  3. Registry & Capability Discovery                  │
│  4. Scheduler & Lifecycle (Cron + Heartbeat)         │
│  5. Forensic Inspector (Audit + Webhooks)            │
│  6. God Mode (Global Kill-Switch + System Prompts)   │
└─────────────────────────────────────────────────────┘
```

---

## 4. Core Components

### 4.1 The Gateway

The Gateway is the single authoritative boundary through which all agent-to-agent and agent-to-system communication flows. It is not a proxy — it is a validator, router, and lifecycle manager.

**Responsibilities:**

| Concern | Mechanism |
|---------|-----------|
| Message validation | Schema Interceptor rejects malformed DecisionLog envelopes; logs Schema Violation events |
| Routing | Routes messages to the correct session, cluster, or capability handler |
| Heartbeat tracking | Evicts dead nodes from the Capability Map when heartbeats stop |
| Cron dispatch | Leader election prevents duplicate dispatch across gateway instances |
| Dynamic scheduling | Agents can request "remind me in N hours" — Gateway creates one-time cron entries |
| Inbound webhooks | External events mapped to agent intents (e.g. GitHub PR → Code Reviewer cluster) |
| Outbound webhooks | Callback on task completion with retry + exponential backoff + Dead Letter Queue |
| HITL relay | Routes Pause/Rewrite/Inject commands from UI back to active agents |
| Cost accounting | Aggregates `state_delta.cumulative_session_cost` per session and per branch |

**Schema Violation Protocol:**
If a DecisionLog fails validation:
1. Message is rejected (not forwarded)
2. `SchemaViolationEvent` is emitted with: `{agent_id, capability_version, violation_reason, raw_payload_hash}`
3. UI node is highlighted in orange (distinct from red=entropy alert, grey=idle)

### 4.2 The DecisionLog Schema

Every message passing through the Gateway is wrapped in a DecisionLog envelope. This is the primitive that makes the entire UI possible — every visualization derives from these fields.

```json
{
  "meta": {
    "trace_id": "uuid-v4",
    "parent_step_id": "uuid-v4-of-previous-node",
    "timestamp": "iso-8601-utc",
    "cluster_id": "aws-eu-central-1-mesh-04"
  },
  "identity": {
    "agent_id": "researcher-alpha-9",
    "agent_type": "web_researcher",
    "capability_version": "v2.1.0-stable"
  },
  "cognition": {
    "intent": "Verify quarterly revenue for NVDA",
    "reasoning_chain": [
      "Initial search returned conflicting dates for fiscal year end.",
      "Cross-referencing SEC EDGAR filings to resolve conflict.",
      "Prioritizing primary source over news aggregator."
    ],
    "confidence_score": 0.94,
    "strategy_used": "ReAct",
    "entropy_score": 0.05
  },
  "action": {
    "tool_call": "serp_search",
    "tool_input": "{\"query\": \"NVDA 10-K revenue 2023\"}",
    "tool_output_summary": "Retrieved 10-K; Revenue confirmed at $26.97B",
    "status": "success"
  },
  "state_delta": {
    "added_to_memory": ["NVDA Fiscal Year ends Jan 28"],
    "tokens_consumed": 1250,
    "cumulative_session_cost": 0.084
  },
  "control": {
    "hitl_required": false,
    "interrupt_signal": null,
    "is_terminal": false
  }
}
```

**UI Derivations:**

| UI Feature | Schema Field |
|------------|-------------|
| Causal topology graph edges | `meta.parent_step_id` |
| Reasoning playback (typewriter) | `cognition.reasoning_chain` |
| Entropy alert (flashing red node) | `cognition.entropy_score` |
| Cost heatmap | `state_delta.cumulative_session_cost` |
| State scrub (hallucination infection point) | `state_delta.added_to_memory` |
| HITL gate activation | `control.hitl_required` |
| Terminal node detection | `control.is_terminal` |

### 4.3 The Topology Map (Macro View)

A Canvas-based engine renders the agent mesh as a live, clickable graph. This is not decorative — operators use it to locate bottlenecks, trace cascades, and issue interventions.

**Requirements:**
- **Multi-layer toggle:** Logical map (algorithmic grouping by capability_type) ↔ Geographical map (cluster_id → region)
- **Clickable edges:** Every link shows traffic volume (messages/sec), latency, and status (Healthy / Alert / Blocked)
- **Hierarchical drill-down:** Cluster Group → Sub-group → Agent Instance, independent of current map context
- **Real-time HUD overlays:** Alarms appear directly on node/edge icons; no separate panel required
- **Node states:** Idle (grey), Active (blue), Alert/Entropy (flashing red), Schema Violation (orange), Dead (dim)
- **1→N fork rendering:** When `parent_step_id` shows one node spawning N children, the topology forks instantly

### 4.4 The Session Drill-down (Micro View / Black Box Flight Recorder)

Per-session view that eliminates the black box. Shows the *reasoning* behind autonomous decisions.

**Requirements:**
- **Reasoning Loop Visibility:** Agent status badge (Thinking / Tool Executing / Waiting / Terminal) + Decision Log panel showing why Option A was chosen over Option B
- **Causal State Graph:** DAG built from `meta.parent_step_id` chains. Each node shows: input/output state, contextual provenance (citations), memory snapshots retrieved for that step
- **Reasoning Playback:** `cognition.reasoning_chain` rendered with typewriter effect for debugging hallucinations
- **Interactive HITL Gates:** Approval buttons on nodes where `control.hitl_required == true`. Human can Edit, Approve, or Reject before the message is forwarded
- **Confidence Indicators:** `cognition.confidence_score` shown per node. Low-confidence nodes are flagged for manual review

### 4.5 The HITL Manual Intervention API

The control path from the UI back through the Gateway to an active agent. Three command types:

| Command | Payload | Behaviour |
|---------|---------|-----------|
| `Pause` | `{session_id, agent_id}` | Gateway buffers all further messages from agent; agent receives "hold" signal |
| `Rewrite` | `{session_id, agent_id, original_message_id, new_content}` | Gateway replaces buffered message content before forwarding |
| `Inject` | `{session_id, agent_id, prompt}` | Gateway injects prompt into agent's next context window |

All three commands are:
- Authenticated (operator identity attached)
- Logged as `HITLInterventionEvent` with before/after state
- Reversible: Unpause restores buffered message queue in order

---

## 5. UI Information Architecture (Six Views)

### View 1: Fleet Command (Macro)
- **Mesh Topology Map** — Canvas-based agent mesh
  - Panel: Real-time throughput (messages/sec)
  - Panel: Cost heatmap by cluster branch
- **Infrastructure Health**
  - Panel: Gateway + Event Bus + DB status
  - Panel: Latency distribution across regions
  - Panel: Active mTLS certificate status

### View 2: Session Cluster Manager
- **Active Session List** — searchable table
  - Panel: Entropy Alerts (looping/stuck sessions)
  - Panel: Total session cost vs. budget cap
- **Session Drill-down**
  - Causal DAG trace
  - Live Scratchpad (real-time `cognition.intent` stream)
  - HITL Console: Pause / Edit Message / Inject Prompt

### View 3: Registry & Capability Discovery
- **Capability Directory** ("Yellow Pages" for agents)
  - Panel: Agent type, healthy instance count
  - Panel: Model version distribution
- **Routing Logic Manager**
  - Panel: Traffic weighting controls (% to Cluster B)
  - Panel: Circuit breaker status per capability

### View 4: Scheduler & Lifecycle
- **Cron Job Dashboard**
  - Panel: Upcoming scheduled tasks + success/failure history
  - Panel: Dead Letter Queue (failed scheduled events)
- **Heartbeat Monitor**
  - Panel: Zombie list (agents that missed check-ins)
  - Panel: Auto-scaling triggers

### View 5: Forensic Inspector
- **Message Archive** — queryable history of all Gateway traffic
  - Panel: Semantic search (find all agents that discussed "Project X")
  - Panel: Cost attribution by Agent ID or Session ID
- **Security & Webhooks**
  - Panel: Webhook log with payload history + signature validation status
  - Panel: Policy Engine (Deny/Allow rules for inter-agent communication)

### View 6: God Mode
- **Global Kill-Switch** — instantly pause all non-essential message routing
- **Global Instructions** — update System Prompt for an entire agent class across all clusters

---

## 6. Implementation Strategy

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI Framework | Phoenix LiveView (existing) | Real-time websockets, existing investment |
| Topology Renderer | Canvas API (v1) → React Flow (v2) | Canvas sufficient for <1000 nodes; React Flow when interaction depth grows |
| Event Bus | PubSub (existing) → NATS (future) | Current PubSub works for single-node; NATS when multi-node required |
| Message Validation | Elixir Ecto changesets | Declarative, testable, matches existing Ash patterns |
| Heartbeat | GenServer with ETS (existing pattern) | AgentMonitor already implements this; extend for Capability Map |
| Cron | Custom GenServer + leader election | Leader election via distributed Erlang or Redis |
| Webhook Retry | Custom GenServer + exponential backoff | DLQ as SQLite table |
| HITL Command Queue | CommandQueue (existing) + new command types | Extends existing file-based inbox pattern |

---

## 7. Key Design Principles

1. **Validation at the boundary, not at the consumer.** The Gateway intercepts malformed messages before they reach any agent or UI component. Consumers can trust that what they receive is schema-valid.

2. **Causality is a first-class field.** `parent_step_id` is not metadata — it is the structural primitive for all topology rendering and drill-down navigation. It must be emitted by every agent on every message.

3. **Entropy detection over manual monitoring.** The entropy_score threshold check runs at the Gateway level. Human operators should be alerted, not expected to detect loops by observation.

4. **Immutable audit trail.** Every DecisionLog message is archived. No message is deleted. The Forensic Inspector requires queryable history of the complete mesh state.

5. **Human-in-the-loop by exception.** The HITL gate activates only when `control.hitl_required == true` or when a human explicitly issues a Pause command. Default is autonomous operation.

6. **Cost visibility at every level.** From individual message cost to session-level accumulation to branch heatmaps — cost data is surfaced everywhere, not hidden in aggregate billing.

---

## 8. Open Questions

| Question | Impact | Resolution Path |
|----------|--------|-----------------|
| Canvas vs React Flow for topology | Rendering performance at >500 nodes | Prototype Canvas first; migrate to React Flow if interaction depth demands it |
| NATS vs Erlang distribution for leader election | Cron dispatch safety at multi-instance scale | Start with single-instance GenServer; design for NATS migration |
| entropy_score computation — who calculates it? | Gateway must understand agent reasoning to compute | Options: agent self-reports, or Gateway compares reasoning chains across time window |
| Semantic search implementation for Message Archive | Full-text vs vector search | SQLite FTS5 for v1; pgvector or Qdrant for v2 |
| mTLS certificate management | Security model for inter-agent communication | Out of scope for v1; flag as infrastructure prerequisite |
| Schema versioning | `capability_version` drift as agents update | Gateway must support N-1 schemas during rolling deploys |

---

## 9. Relation to Existing Observatory ADRs

This project brief defines the **next evolutionary phase** of Observatory. Existing ADRs (001-012) remain valid — the navigation structure (ADR-001/003), messaging architecture (ADR-004/005), dual data sources (ADR-012), and component patterns (ADR-010/011) all carry forward.

New ADRs (013-022) extend these with hypervisor-specific decisions.

---

## 10. ADR Index (Extracted from this Brief)

| ADR | Title | Decision Area |
|-----|-------|---------------|
| ADR-013 | Hypervisor Platform Scope | Platform evolution: Observatory → Hypervisor |
| ADR-014 | DecisionLog Universal Message Envelope | Schema standard for all Gateway messages |
| ADR-015 | Gateway Schema Interceptor | Validation, rejection, and violation logging |
| ADR-016 | Canvas-Based Topology Map Renderer | Macro fleet visualization engine choice |
| ADR-017 | Causal DAG via parent_step_id | Topology and drill-down graph construction |
| ADR-018 | Entropy Score as Loop Detection Primitive | Algorithmic agent loop detection |
| ADR-019 | Heartbeat and Leader Election for Gateway | Multi-instance cron dispatch safety |
| ADR-020 | Webhook Reliability: Retry + DLQ | Outbound webhook durability pattern |
| ADR-021 | HITL Manual Intervention API | Operator control path: Pause/Rewrite/Inject |
| ADR-022 | Six-View UI Information Architecture | Hypervisor UI sitemap and view responsibilities |
