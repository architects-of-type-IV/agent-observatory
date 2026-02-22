---
id: ADR-015
title: Gateway Schema Interceptor
date: 2026-02-21
status: proposed
related_tasks: []
parent: ADR-014
superseded_by: null
---
# ADR-015 Gateway Schema Interceptor
[2026-02-21] proposed

## Related ADRs
- [ADR-014](ADR-014-decision-log-envelope.md) DecisionLog Universal Message Envelope (parent)
- [ADR-013](ADR-013-hypervisor-platform-scope.md) Hypervisor Platform Scope

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief §4.1 | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | Gateway Interceptor Requirement and Schema Violation Protocol |

## Context

The Gateway receives raw JSON messages from agents. Before routing, it must determine whether a message is schema-valid. If it is not, the message must be rejected — not silently dropped, not partially forwarded. The rejection must be observable to the operator so they can identify which agent version is "going rogue" with its reporting.

Three questions need answering:
1. Where in the message lifecycle does validation happen?
2. What is the contract for rejection (what does the agent receive, what does the operator see)?
3. How is the violation persisted and surfaced?

## Options Considered

1. **Validate at routing layer** — Each consumer validates messages as it receives them. Invalid messages fail silently in one consumer but may succeed in another.
   - Con: No single enforcement point. Different consumers may accept different subsets. Schema violations are undetectable at the system level.

2. **Validate at Gateway ingress, reject before routing** — A dedicated GenServer (`SchemaInterceptor`) receives all inbound messages first, validates against the DecisionLog changeset, and either forwards to the router or emits a `SchemaViolationEvent`.
   - Pro: Single enforcement point. All consumers guaranteed schema-valid input. Violations are observable.
   - Con: Adds latency of one GenServer hop per message. Acceptable at message frequencies observed in Claude Code mesh (<100 msg/s per session).

3. **Validate asynchronously (optimistic routing)** — Route immediately; validate concurrently; emit violation event if invalid but message has already been forwarded.
   - Con: Consumers may process invalid messages before violation is detected. Defeats the purpose of the interceptor.

## Decision

**Option 2** — Synchronous validation at Gateway ingress via `Observatory.Gateway.SchemaInterceptor` GenServer.

**Message lifecycle:**

```
Agent → POST /gateway/messages
          │
          ▼
     SchemaInterceptor.validate/1
          │
    ┌─────┴─────┐
    │ valid     │ invalid
    ▼           ▼
  Router    SchemaViolationEvent
  routes      │
  to topic    ├── Reject with HTTP 422
              ├── Persist violation log entry
              └── Broadcast to UI via PubSub "gateway:violations"
```

**SchemaViolationEvent fields:**
```json
{
  "event_type": "schema_violation",
  "timestamp": "iso-8601-utc",
  "agent_id": "researcher-alpha-9",
  "capability_version": "v2.1.0-stable",
  "violation_reason": "missing required field: meta.trace_id",
  "raw_payload_hash": "sha256:abc123..."
}
```

Note: `raw_payload_hash` (not the raw payload itself) is stored. Full payloads are not persisted on violation — they may contain sensitive data and we cannot trust their content.

**UI rendering of violations:**
- Node in topology map highlighted **orange** (distinct from entropy red, idle grey)
- Forensic Inspector shows violation events in a dedicated "Schema Violations" filter
- Flash notification in Fleet Command view: "Agent researcher-alpha-9 (v2.1.0) sent malformed message"

**Rejection response to agent:**
```json
{
  "status": "rejected",
  "reason": "schema_violation",
  "detail": "missing required field: meta.trace_id",
  "trace_id": null
}
```

## Rationale

Synchronous validation is the only option that gives a meaningful enforcement guarantee. The latency cost (one extra GenServer call) is negligible at observed message rates. The hash-only persistence policy protects against storing malformed or potentially adversarial content while still giving operators enough to diagnose which agent version is failing.

Storing the hash (not payload) mirrors standard security logging practice — you record that something suspicious arrived, not the suspicious content itself.

## Consequences

- New module: `lib/observatory/gateway/schema_interceptor.ex`
- New Ash resource or ETS table: `SchemaViolation` events (for Forensic Inspector queries)
- PubSub topic: `"gateway:violations"` — UI subscribes for real-time violation alerts
- HTTP 422 response to agents on schema violation
- Topology map node state extended: `:schema_violation` (orange) added to existing node state set
- All agent SDKs must handle 422 responses and log them
