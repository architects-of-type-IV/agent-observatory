---
id: ADR-021
title: HITL Manual Intervention API
date: 2026-02-21
status: proposed
related_tasks: []
parent: ADR-013
superseded_by: null
---
# ADR-021 HITL Manual Intervention API
[2026-02-21] proposed

## Related ADRs
- [ADR-013](ADR-013-hypervisor-platform-scope.md) Hypervisor Platform Scope (parent)
- [ADR-014](ADR-014-decision-log-envelope.md) DecisionLog Universal Message Envelope
- [ADR-018](ADR-018-entropy-score-loop-detection.md) Entropy Score as Loop Detection Primitive
- [ADR-022](ADR-022-six-view-ui-architecture.md) Six-View UI Information Architecture

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief §4.5 | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | HITL Manual Intervention API: Pause/Rewrite/Inject |

## Context

Human-in-the-loop intervention is the mechanism by which an operator takes control of an autonomous agent's message flow. Three scenarios trigger this:

1. **Proactive gate** — An agent sets `control.hitl_required == true` in its DecisionLog, signalling that it needs human approval before the action is executed (e.g., "about to execute a purchase").
2. **Reactive intervention** — An entropy alert fires; operator clicks "Pause and Inspect" (ADR-018).
3. **Manual operator action** — Operator decides to intervene without any trigger.

The question is how the command travels from the UI → Gateway → Agent, and how it is authenticated, logged, and reversed.

## Options Considered

**Command delivery mechanism:**

1. **HTTP command endpoint** — UI issues `POST /gateway/sessions/:session_id/commands` with command type and payload. Gateway relays to agent via existing CommandQueue.
   - Pro: Stateless, auditable, RESTful.
   - Con: Gateway must know agent's CommandQueue path. Adds coupling.

2. **PubSub relay** — UI pushes command to PubSub topic `"session:commands:{session_id}"`. Gateway subscribes and relays to agent's inbox.
   - Pro: Decoupled. Gateway already subscribes to session topics.
   - Con: PubSub is fire-and-forget; no delivery guarantee without additional bookkeeping.

3. **Extend existing CommandQueue + HTTP endpoint** — Define new command types in the existing CommandQueue file format. UI calls a new HTTP endpoint; Gateway writes the command file to the agent's inbox.
   - Pro: Reuses existing proven infrastructure (CommandQueue already delivers commands to agents).
   - Con: File-based delivery has latency (agents poll every 2s).

## Decision

**Option 3** — Extend CommandQueue with three new command types.

**New command types:**

```json
// Pause: Gateway stops forwarding DecisionLog messages from this agent
{
  "type": "hitl_pause",
  "session_id": "...",
  "agent_id": "...",
  "operator_id": "...",
  "reason": "Entropy loop detected",
  "timestamp": "iso-8601-utc"
}

// Rewrite: Gateway replaces content of the buffered message
{
  "type": "hitl_rewrite",
  "session_id": "...",
  "agent_id": "...",
  "original_trace_id": "uuid-of-buffered-message",
  "new_content": "...",
  "operator_id": "...",
  "timestamp": "iso-8601-utc"
}

// Inject: Gateway adds a new prompt to the agent's next context
{
  "type": "hitl_inject",
  "session_id": "...",
  "agent_id": "...",
  "prompt": "Stop your current approach. Try X instead.",
  "operator_id": "...",
  "timestamp": "iso-8601-utc"
}

// Unpause: Resume normal message forwarding
{
  "type": "hitl_unpause",
  "session_id": "...",
  "agent_id": "...",
  "operator_id": "...",
  "timestamp": "iso-8601-utc"
}
```

**Gateway Pause state machine:**

```
Normal → [hitl_pause] → Paused → [hitl_unpause] → Normal
                            │
                    Agent messages buffered in ETS
                            │
                    [hitl_rewrite] → Replace buffer entry
                    [hitl_inject]  → Prepend to next forward
```

While paused, the Gateway's `HITLRelay` module buffers incoming DecisionLog messages from the agent in an ETS table keyed by `{session_id, agent_id}`. On Unpause, buffered messages are forwarded in order, with any Rewrite applied.

**HTTP endpoints (new):**
```
POST /gateway/sessions/:session_id/pause
POST /gateway/sessions/:session_id/unpause
POST /gateway/sessions/:session_id/rewrite
POST /gateway/sessions/:session_id/inject
```

All endpoints require an `operator_id` claim (simple API key in v1; OAuth in v2).

**Audit trail:**

Every HITL command is persisted as a `HITLInterventionEvent` in an Ash resource:

```elixir
# Fields: id, session_id, agent_id, operator_id, command_type,
#         before_state (DecisionLog hash), after_state (DecisionLog hash),
#         timestamp, reversed_at
```

The Session Drill-down renders HITL intervention nodes inline in the DAG — a distinct node shape (diamond) appears at the point of intervention.

**`control.hitl_required` handling:**

When the Gateway's Schema Interceptor sees `control.hitl_required == true`:
1. Immediately enters Pause state for that agent
2. Buffers the triggering message
3. Broadcasts `HITLGateOpenEvent` to `"session:hitl:{session_id}"` PubSub topic
4. UI displays the approval gate in the Session Drill-down with the buffered message content

Operator actions: **Approve** (Unpause, message forwarded as-is) | **Rewrite** (edit + Unpause) | **Reject** (Unpause with inject: "action rejected by operator, do not retry").

## Rationale

Extending CommandQueue reuses the file-based delivery channel already proven for agent-dashboard messaging. The 2-second poll latency is acceptable for human-in-the-loop scenarios (humans take longer than 2 seconds to decide). The ETS pause buffer is fast and does not require a DB write per buffered message.

The audit trail (HITLInterventionEvent with before/after state hashes) provides the "state scrubbing" capability described in the brief — operators can trace exactly what was changed, by whom, and when.

## Consequences

- New module: `lib/observatory/gateway/hitl_relay.ex` (pause state machine, buffer, relay)
- New ETS table: HITL pause buffers keyed by `{session_id, agent_id}`
- New HTTP endpoints (4): pause, unpause, rewrite, inject
- New Ash resource: `HITLInterventionEvent`
- New PubSub topic: `"session:hitl:{session_id}"` — gate open/close events
- Session Drill-down gains HITL gate UI (ADR-022 View 2)
- Existing CommandQueue carries new command type files; agent SDK must handle `hitl_*` types
- Operator authentication: API key header `X-Observatory-Operator-Id` in v1
