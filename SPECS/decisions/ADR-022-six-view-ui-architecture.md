---
id: ADR-022
title: Six-View UI Information Architecture
date: 2026-02-21
status: proposed
related_tasks: []
parent: ADR-013
superseded_by: null
---
# ADR-022 Six-View UI Information Architecture
[2026-02-21] proposed

## Related ADRs
- [ADR-013](ADR-013-hypervisor-platform-scope.md) Hypervisor Platform Scope (parent)
- [ADR-001](../decisions/ADR-001-swarm-control-center-nav.md) Swarm Control Center Navigation (existing, being superseded)
- [ADR-003](../decisions/ADR-003-unified-control-plane.md) Unified Control Plane (existing, being superseded)
- [ADR-016](ADR-016-canvas-topology-renderer.md) Canvas-Based Topology Map Renderer
- [ADR-017](ADR-017-causal-dag-parent-step-id.md) Causal DAG via parent_step_id
- [ADR-021](ADR-021-hitl-intervention-api.md) HITL Manual Intervention API

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief §5 | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | Six-View UI Information Architecture sitemap |
| ADR-001 | Existing SPECS/decisions/ | Previous nav restructure (4 primary + overflow) |

## Context

The existing Observatory dashboard (ADR-001/003) has 7 tabs: Command, Pipeline, Agents, Protocols, Feed, Errors, plus a "More" dropdown. This structure was designed for swarm monitoring — a narrower problem than the Hypervisor requires.

The Hypervisor adds: Topology Map, Session Drill-down with HITL, Capability Registry, Cron Scheduler, Forensic Inspector, and God Mode. These do not map cleanly onto the existing 7-tab structure. The question is whether to extend the existing structure or replace it.

## Options Considered

1. **Extend existing 7 tabs** — Add Topology Map to Command, add Forensic Inspector to errors, etc. Squeeze new capabilities into existing nav.
   - Pro: Less migration work. Existing keyboard shortcuts preserved.
   - Con: The existing tabs are swarm-centric (Command, Pipeline, Protocols). These concepts don't exist at the Hypervisor level. Forcing Hypervisor features into swarm-centric containers produces incoherent views.

2. **Replace with six Hypervisor views** — Redesign nav from scratch. Six primary views matching the six functional areas of the Hypervisor. Swarm-specific views (Pipeline, Protocols) are absorbed into higher-level Hypervisor views.
   - Pro: Clean conceptual model. Each view answers a specific operational question.
   - Con: Breaks existing keyboard shortcuts. Operators who know the current dashboard must relearn.

3. **Side-by-side mode selector** — Two nav modes: "Swarm Mode" (existing 7 tabs) and "Hypervisor Mode" (6 new views). User switches between them.
   - Pro: No breaking change. Gradual migration.
   - Con: Two navigation models creates cognitive overhead. Features developed for one mode may not appear in the other. Maintenance burden doubles.

## Decision

**Option 2** — Replace with six Hypervisor views. Existing swarm-specific views are absorbed as sub-panels within the Hypervisor architecture.

**Six views and their operational questions:**

| # | View Name | Operational Question |
|---|-----------|---------------------|
| 1 | Fleet Command | "What is the health and topology of my entire mesh right now?" |
| 2 | Session Cluster | "What is happening inside this specific session, and can I intervene?" |
| 3 | Registry | "What capabilities exist, what's routing where, what's healthy?" |
| 4 | Scheduler | "What is scheduled, what failed, what agents are alive?" |
| 5 | Forensic Inspector | "What happened, who spent what, what went wrong in history?" |
| 6 | God Mode | "Override the mesh — pause everything or update global instructions." |

**Keyboard shortcuts (reassigned):**

| Key | View |
|-----|------|
| `1` | Fleet Command |
| `2` | Session Cluster |
| `3` | Registry |
| `4` | Scheduler |
| `5` | Forensic Inspector |
| `6` | God Mode |
| `Esc` | Close drill-down / return to Fleet Command |

**View 1: Fleet Command (replaces Command + Pipeline)**
- Primary: Mesh Topology Map (Canvas, ADR-016)
- Secondary panels: Real-time throughput, Cost heatmap, Infrastructure health, Latency distribution, mTLS status
- Inherits: Agent grid from current Command view

**View 2: Session Cluster (replaces Agents + current session panels)**
- Primary: Active Session List with Entropy Alert filter
- Drill-down: Causal DAG (ADR-017), Live Scratchpad, HITL Console (ADR-021)
- Inherits: Agent detail panel from current Agents view

**View 3: Registry (new)**
- Capability Directory: agent types, instance counts, model version distribution
- Routing Logic Manager: traffic weighting sliders, circuit breaker status
- No equivalent in existing nav

**View 4: Scheduler (new, absorbs Protocols partially)**
- Cron Job Dashboard: upcoming tasks, success/failure history
- DLQ panel: failed scheduled events (ADR-020)
- Heartbeat Monitor: zombie list (ADR-019), auto-scaling triggers

**View 5: Forensic Inspector (replaces Errors + Analytics + Timeline)**
- Message Archive: full-text queryable history, semantic search
- Cost attribution: by Agent ID or Session ID
- Security: Webhook log + signature validation status
- Policy Engine: Deny/Allow rules
- Inherits: Error list, analytics, timeline from current views

**View 6: God Mode (new)**
- Global Kill-Switch: pause all non-essential routing (single large button, confirmation required)
- Global Instructions: text editor for system prompt per agent class, "Push to all" button
- Danger zone UI styling (red borders, explicit confirmation dialogs)

**Migration of existing views:**
- Feed → sub-panel in Session Cluster drill-down (raw event stream for a session)
- Messages → sub-panel in Session Cluster (inter-agent message thread)
- Tasks → available in Session Cluster agent detail sidebar
- Protocols → absorbed into Session Cluster (messaging protocol traces)
- Analytics → absorbed into Forensic Inspector
- Timeline → absorbed into Forensic Inspector and Session Cluster

## Rationale

The existing nav structure was built for swarm monitoring and reflects it. The Hypervisor is a different product with different operator workflows. Option 3 (mode selector) would maintain two parallel nav trees forever — a maintenance and UX burden that grows with every new feature.

The six views map directly to the six functional areas the operator needs to answer operational questions. Each view has a clear primary concern and can be built and tested independently.

Existing features are not deleted — they are absorbed as sub-panels within the new structure. The Feed, Messages, and Tasks views that operators currently use become focused drill-down panels rather than top-level nav items.

## Consequences

- Existing `:command`, `:pipeline`, `:agents`, `:protocols`, `:feed`, `:errors`, `:analytics`, `:timeline` view_mode atoms replaced by `:fleet_command`, `:session_cluster`, `:registry`, `:scheduler`, `:forensic`, `:god_mode`
- Keyboard shortcuts 1-6 reassigned
- `localStorage` view_mode state will mismatch on upgrade — handled by rescue in navigation handlers (default to `:fleet_command`)
- Six new LiveView component modules (one per view)
- Existing component modules (FeedComponents, CommandComponents, etc.) become sub-panel components imported into the new view modules
- ADR-001 and ADR-003 status updated to `superseded_by: ADR-022`
- God Mode requires explicit operator confirmation UI (double-confirm pattern for kill-switch)
