---
id: ADR-004
title: Messaging Architecture Aligned with Claude Code Native
date: 2026-02-15
status: accepted
related_tasks: []
parent: null
superseded_by: null
---
# ADR-004 Messaging Architecture Aligned with Claude Code Native
[2026-02-15] accepted

## Related ADRs
- [ADR-005](ADR-005-ets-over-database.md) ETS for Messaging over Database
- [ADR-006](ADR-006-dead-ash-domains.md) Dead Ash Domains Replaced with Plain Modules

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Messaging Architecture Investigation | [CONV-002](../conversations/CONV-002-messaging-architecture.md) | Full investigation: 4-agent diagnosis, option analysis, quick fix + migration plan |
| Quick fix commit | `40a5aa38` | Unified all 4 forms through Mailbox, added PubSub subscription |
| Session JSONL (investigation) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/16482e4f-50b6-4152-99ce-82a7f7e604c4.jsonl` | Raw session transcript |
| Session JSONL (fix) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/40a5aa38-28e8-4f70-a5ba-21602f618f07.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-15T01:44:53Z | Researcher confirmed custom inbox is NOT standard Claude Code |
| 2026-02-15T01:50:27Z | Protocol analyst recommends Option B with pragmatic staging |
| 2026-02-15T01:51:58Z | User approved Option B |

## Context

Observatory had two competing inbox systems that didn't talk to each other:
- **Custom:** `~/.claude/inbox/{session_id}/{id}.json` (Observatory invention, backed by CommandQueue GenServer)
- **Native:** `~/.claude/teams/{team}/inboxes/{agent}.json` (Claude Code standard team messaging)

Dashboard-to-agent messages went to the custom path. Agents using Claude Code's native SendMessage tool never saw them. Agent-to-dashboard messages arrived in ETS via MCP but the dashboard wasn't subscribed to the `"agent:dashboard"` PubSub topic. Neither direction worked reliably.

Additionally, 164 stale CommandQueue files (704KB) had accumulated because `acknowledge_message` only updated ETS, not the filesystem. No message ordering guarantees existed across the three channels (ETS, CommandQueue, PubSub).

## Options Considered

1. **Option A (Fix current)** -- Add PubSub subscription, fix acknowledge_message cleanup, keep custom system. Quick (hours) but perpetuates the architectural split between two inbox formats.
2. **Option B (Align with Claude Code native)** -- 3-stage rollout: parallel write to both paths, switch reads to native, remove old system. Unifies into one messaging path. Makes dashboard a natural team member.
3. **Option C (Database-backed)** -- Replace both with an Ash resource and Postgres. Most robust persistence and querying, but heaviest lift and overkill for transient agent messages.
4. **Option D (Hybrid)** -- Keep both systems, add a bridge layer. Complexity grows, technical debt accumulates.

## Decision

Option B with pragmatic staging. Quick fixes applied immediately to unblock usage:
1. Dashboard subscribes to `"agent:dashboard"` PubSub topic
2. Dashboard sets `:current_session_id` assign to `"dashboard"`
3. All 4 message forms routed through `Mailbox.send_message` for consistent ETS + CommandQueue + PubSub delivery
4. Form refresh prevented with `phx-update="ignore"` wrapper + `ClearFormOnSubmit` JS hook

Full migration to Claude Code native messaging paths planned as follow-up work.

## Rationale

The custom inbox system was an Observatory invention that predated understanding of Claude Code's native team messaging protocol. Aligning with the standard path makes the dashboard a natural team member (just another agent in the team config) and eliminates the impedance mismatch between how Observatory sends messages and how Claude Code agents receive them.

Quick fixes unblock immediate use while the full migration proceeds incrementally. The three-stage rollout (parallel write, switch reads, remove old) ensures zero message loss during transition.

## Consequences

- **Immediate:** Dashboard receives agent messages in real-time. Form inputs persist across re-renders.
- **Pending:** Full native messaging migration not yet complete
- **Known debt:** 164 stale CommandQueue files not yet cleaned. No ordering guarantees. ETS memory growth unbounded. Duplicate delivery risk on Phoenix restart (ETS cleared, CommandQueue replayed).
- **Architecture:** Mailbox remains the single routing point for all message sends (dual-write to ETS + CommandQueue + PubSub)
