---
id: ADR-006
title: Dead Ash Domains Replaced with Plain Modules
date: 2026-02-15
status: accepted
related_tasks: []
parent: null
superseded_by: null
---
# ADR-006 Dead Ash Domains Replaced with Plain Modules
[2026-02-15] accepted

## Related ADRs
- [ADR-005](ADR-005-ets-over-database.md) ETS for Messaging over Database

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Messaging Architecture Investigation | [CONV-002](../conversations/CONV-002-messaging-architecture.md) | Dead code audit ran as Phase 3 of messaging investigation |
| Session JSONL | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/16482e4f-50b6-4152-99ce-82a7f7e604c4.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-15T01:19:32Z | Scout-backend: 8 findings across backend modules |
| 2026-02-15T01:21:37Z | Stage 1 consolidated: 23 instances across ~20 files |
| 2026-02-15T01:22:32Z | Stage 2 verified: 19 confirmed, 2 false positives rejected |

## Context

Three Ash domains existed in the codebase that were never connected to real data flows:
- **Messaging** (`lib/observatory/messaging.ex`, `messaging/message.ex`) -- Message Ash resource with schema, never used for actual message routing
- **TaskBoard** (`lib/observatory/task_board.ex`, `task_board/task.ex`) -- Task Ash resource, unused because tasks come from `tasks.jsonl` via TaskManager
- **Annotations** (`lib/observatory/annotations.ex`, `annotations/note.ex`) -- Note Ash resource, replaced by Notes GenServer with ETS

These domains added compilation overhead, import confusion, and dead code warnings without providing value.

## Options Considered

1. **Wire the Ash domains to real data** -- High effort, wrong abstraction for ephemeral data (see ADR-005)
2. **Remove domains, keep plain module replacements** -- Mailbox GenServer, TaskManager plain module, and Notes GenServer already handled all real data flows
3. **Keep domains as stubs for future use** -- Accumulates dead code, confuses new sessions reading the codebase

## Decision

Remove all three Ash domains. Move files to `tmp/trash/dead-code-audit/` (soft delete per project convention). The plain module replacements (Mailbox, TaskManager, Notes) remain as the canonical implementations.

## Rationale

The Ash domains were over-engineered for ephemeral data. Plain GenServers with ETS provide the exact semantics needed (fast reads, PubSub integration, no persistence requirements) with far less ceremony. The Ash framework excels for persistent resources that need CRUD, policies, and API generation -- but agent messages, task state from `tasks.jsonl`, and ephemeral annotations don't benefit from that machinery.

## Consequences

- **Removed:** 6 files (3 domain modules + 3 resource modules) moved to `tmp/trash/dead-code-audit/`
- **Remaining:** 3 active Ash domains (Events, AgentTools, Costs) that handle persistent data
- **Zero warnings:** `mix compile --warnings-as-errors` passes clean after removal
- **Pattern established:** Use Ash for persistent, queryable resources. Use plain GenServers for ephemeral, real-time coordination data.
