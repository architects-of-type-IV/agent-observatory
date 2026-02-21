---
id: ADR-013
title: Hypervisor Platform Scope
date: 2026-02-21
status: proposed
related_tasks: []
parent: null
superseded_by: null
---
# ADR-013 Hypervisor Platform Scope
[2026-02-21] proposed

## Related ADRs
- [ADR-001](../decisions/ADR-001-swarm-control-center-nav.md) Swarm Control Center Navigation (existing, carries forward)
- [ADR-014](ADR-014-decision-log-envelope.md) DecisionLog Universal Message Envelope
- [ADR-022](ADR-022-six-view-ui-architecture.md) Six-View UI Information Architecture

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | Full requirements and architecture |

## Context

Observatory (as of ADR-012) is a single-node Phoenix LiveView application that passively monitors Claude Code agents via hook events. It observes but cannot govern: it can show that an agent ran a Bash command but cannot explain why, cannot interrupt it, cannot enforce routing policy, and cannot trace cost to a causal branch.

The user's requirements describe a qualitatively different system: one that validates all messages at a boundary, renders a live mesh topology, enables reasoning trace playback, and provides manual intervention channels. These capabilities require extending Observatory's architecture, not just adding views to the existing dashboard.

The core question is scope: do we incrementally add hypervisor features to the existing dashboard, or do we define a distinct Hypervisor layer that Observatory's existing UI can plug into?

## Options Considered

1. **Incremental addition to existing dashboard** — Add new GenServers, new tabs, new components to the current codebase. No architectural seam between "observer" and "hypervisor" modes.
   - Pro: No migration; existing code continues to work
   - Con: The Gateway (schema interceptor, heartbeat manager, cron scheduler, webhook router) does not belong in a single Phoenix app's supervision tree. Conflating them creates a monolith that cannot be scaled or deployed independently.

2. **Hypervisor as a distinct Elixir application in the same umbrella** — Define `Observatory.Gateway` as a separate OTP application. UI remains Phoenix LiveView; Gateway is a supervised set of GenServers that could be extracted to a separate node.
   - Pro: Clear separation. Gateway can be deployed independently. UI communicates with Gateway via PubSub (local) or NATS (distributed).
   - Con: Umbrella app adds complexity to the current flat structure.

3. **Define Hypervisor as a logical layer within the existing app, with strict module boundaries** — Gateway modules live in `lib/observatory/gateway/`, UI modules in `lib/observatory_web/`. No new mix project. Boundaries enforced by module naming and code review.
   - Pro: Minimal structural change; fastest path to working features
   - Con: Harder to extract later if multi-node deployment is needed

## Decision

**Option 3** — Define the Hypervisor as a logical layer within the existing Observatory application, with strict module boundaries:

- `lib/observatory/gateway/` — Schema Interceptor, Capability Map, HeartbeatManager, CronScheduler, WebhookRouter, HITLRelay
- `lib/observatory/mesh/` — DecisionLog schema, topology graph construction, entropy computation
- `lib/observatory_web/` — unchanged; all existing views carry forward

This approach allows the full hypervisor feature set to be built and validated before any infrastructure extraction is needed. The module boundaries are designed so that extracting Gateway to a separate node later requires only changing process communication (PubSub → NATS), not restructuring business logic.

## Rationale

The immediate constraint is time-to-working-system. Option 2 requires umbrella migration before any hypervisor feature can be built. Option 3 provides the same logical separation without the migration cost. The module boundary discipline (no circular deps between `gateway/` and `mesh/`) enforces the same architectural cleanliness that Option 2 would enforce structurally.

The future path to multi-node deployment is: `gateway/` modules → separate Elixir release → PubSub replaced with NATS subscriptions. This migration is straightforward because the Gateway never holds UI state, and the UI never calls Gateway internals directly.

## Consequences

- New top-level directory: `lib/observatory/gateway/`
- New top-level directory: `lib/observatory/mesh/`
- Existing `lib/observatory/` modules carry forward unchanged
- No new mix project; no umbrella migration
- Gateway modules must not import `ObservatoryWeb` modules
- UI modules must not call Gateway modules directly — all communication via PubSub topics
- Future multi-node extraction path is defined but not yet implemented
