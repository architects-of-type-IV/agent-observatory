---
id: ADR-005
title: ETS for Messaging over Database
date: 2026-02-14
status: accepted
related_tasks: []
parent: null
superseded_by: null
---
# ADR-005 ETS for Messaging over Database
[2026-02-14] accepted

## Related ADRs
- [ADR-004](ADR-004-messaging-architecture.md) Messaging Architecture
- [ADR-006](ADR-006-dead-ash-domains.md) Dead Ash Domains Replaced with Plain Modules

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Messaging Architecture Investigation | [CONV-002](../conversations/CONV-002-messaging-architecture.md) | ETS trade-offs documented by reliability analyst; Option C (database) rejected |
| Team Inspector Design | [CONV-003](../conversations/CONV-003-team-inspector.md) | Scout-messaging confirmed Mailbox struct shape as plain ETS map |
| Session JSONL (inspector) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/8585be9e-149a-4133-bed8-ef55dd380dc9.jsonl` | Raw session transcript |
| Session JSONL (messaging) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/16482e4f-50b6-4152-99ce-82a7f7e604c4.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-14T23:53:40Z | Scout-messaging reported Mailbox struct shape: plain map in ETS |
| 2026-02-15T01:50:06Z | Reliability analyst: ETS trade-offs -- ephemeral, no ordering, unbounded growth |
| 2026-02-15T01:50:27Z | Option C (database) rejected as "overkill for transient agent messages" |

## Context

Agent messages in the Observatory are transient coordination signals -- task assignments, status reports, shutdown requests. They have value during a swarm session (minutes to hours) but not beyond. The system needed a message store that could be built quickly, handle real-time PubSub broadcasts, and not require database migrations.

An Ash-backed Messaging domain with a Message resource existed early in development but was never wired to real message flows.

## Options Considered

1. **Ash resource + Postgres** -- Full persistence, queryable, survives restarts. But requires migrations, schema maintenance, and is overkill for ephemeral data that's stale after a session ends.
2. **ETS + CommandQueue (filesystem)** -- Lightweight, no migrations, fast for real-time PubSub integration. Ephemeral by nature (ETS cleared on restart). CommandQueue provides filesystem durability for agent inbox polling.
3. **Redis or external store** -- Additional infrastructure dependency. Not justified for a single-node monitoring tool.

## Decision

ETS via a Mailbox GenServer (151 lines) + CommandQueue GenServer (237 lines) for filesystem durability. Messages stored as plain maps in ETS (`:observatory_mailboxes` table). CommandQueue writes JSON files to `~/.claude/inbox/{session_id}/` for agents that poll via MCP.

## Rationale

Agent messages are inherently transient -- they coordinate work that happens in minutes, not days. The overhead of an Ash resource, migrations, and database queries is not justified for data with a lifespan measured in hours. ETS provides sub-millisecond reads and natural integration with PubSub broadcasting. The filesystem CommandQueue provides durability for the MCP polling pattern that agents use.

The Ash Messaging domain was removed in a subsequent dead code audit (ADR-006) because it was never connected to real message flows.

## Consequences

- **Positive:** Fast development, no migrations, natural PubSub integration, lightweight GenServer supervision
- **Accepted trade-offs:**
  - Messages lost on Phoenix restart (ETS is ephemeral)
  - No message ordering guarantees across ETS/CommandQueue/PubSub channels
  - ETS memory grows without bounds (mitigated by 24h cleanup interval for read messages)
  - Duplicate delivery risk after crash (ETS cleared but CommandQueue files remain)
- **Mitigation:** CommandQueue files provide a fallback replay path, and the 24h ETS cleanup prevents unbounded growth during normal operation
