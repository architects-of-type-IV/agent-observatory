# Messaging Architecture Investigation

**Date**: 2026-02-15
**Topic**: Diagnosing and fixing the dual messaging system failure
**Status**: Complete
**Session**: `16482e4f-50b6-4152-99ce-82a7f7e604c4`

## Referenced ADRs

| ADR | Title | Relevance |
|-----|-------|-----------|
| [ADR-004](../decisions/ADR-004-messaging-architecture.md) | Messaging Architecture | Primary outcome -- align with Claude Code native |
| [ADR-005](../decisions/ADR-005-ets-over-database.md) | ETS over Database | Validates existing ETS choice, documents trade-offs |
| [ADR-006](../decisions/ADR-006-dead-ash-domains.md) | Dead Ash Domains | Dead code audit removed unused Messaging domain |

## Context

Messaging between dashboard and agents was broken in both directions. User reported form fields losing input on typing. Multi-agent investigation team deployed to diagnose root causes.

## Research

### Phase 1: Parallel Investigation (4 agents)

**Researcher** findings:
- `~/.claude/inbox/{session_id}/` is a custom Observatory invention, NOT a standard Claude Code path
- Claude Code's native team messaging uses `~/.claude/teams/{team}/inboxes/{agent}.json`
- The two systems write to different paths -- messages sent from dashboard never reach agents

**Protocol Tracer** findings (5 critical gaps):
1. Dashboard never subscribes to `"agent:dashboard"` PubSub topic
2. `subscribe_to_mailboxes()` only subscribes to agent sessions, not "dashboard"
3. No `:current_session_id` assign set in mount()
4. CommandQueue writes to `~/.claude/inbox/dashboard/` but nobody reads those files
5. `handle_info` for `{:new_mailbox_message, _}` exists but never fires (PubSub not subscribed)

**UI Analyst** findings:
- Root cause: 1-second `:tick` timer calls `prepare_assigns()` which recreates `:teams` assign
- `message_composer` component receives new teams list reference every tick
- LiveView diffing sees changed prop, re-renders component, destroys form DOM state

**Reliability Analyst** findings (6 issues):
1. CRITICAL: CommandQueue file accumulation -- 164 files (704KB), never cleaned
2. CRITICAL: Duplicate delivery risk -- ETS cleared on restart, CommandQueue replayed
3. CRITICAL: Message loss on Phoenix restart -- ETS ephemeral
4. MEDIUM: No message ordering guarantees across 3 channels
5. MEDIUM: ETS memory growth -- no TTL, mark_read doesn't remove
6. MEDIUM: Multi-tab dashboard identity confusion

### Phase 2: Architecture Options

**Protocol Analyst** evaluated 4 options:

| Option | Approach | Effort | Risk |
|--------|----------|--------|------|
| A | Fix current (PubSub sub + cleanup) | Hours | Perpetuates split |
| B | Align with Claude Code native | Days | Migration complexity |
| C | Database-backed (Ash resource) | Week | Overkill for ephemeral data |
| D | Hybrid bridge layer | Days | Debt accumulates |

Recommendation: **Option B with pragmatic staging** -- quick fixes now, full migration later.

## Decisions

| Topic | Decision | Rationale | ADR |
|-------|----------|-----------|-----|
| Architecture | Option B: align with Claude Code native | Unifies two competing inbox systems | ADR-004 |
| Quick fix | PubSub subscription + phx-update="ignore" | Unblocks immediate use | ADR-004 |
| Form refresh | ClearFormOnSubmit JS hook + phx-update="ignore" wrapper | phx-update forms can't be server-re-rendered | ADR-004 |
| All 4 forms | Route through Mailbox.send_message | Consistent dual-write (ETS + CommandQueue + PubSub) | ADR-004 |
| ETS choice | Keep ETS for messaging (not database) | Ephemeral data, no migrations, fast PubSub | ADR-005 |

### Dead Code Audit (same session, Phase 3)

Spawned 4 scout agents to audit dead code. Found and verified:
- 3 unused Ash domains (Messaging, TaskBoard, Annotations) -- replaced by plain modules
- 4 unused functions across backend modules
- 6 dead component imports

| Topic | Decision | Rationale | ADR |
|-------|----------|-----------|-----|
| Ash domains | Remove Messaging, TaskBoard, Annotations | Never wired to real flows; plain GenServers handle all data | ADR-006 |

## Next Steps

- [x] Apply quick fixes (PubSub subscription, form refresh)
- [x] Unify all 4 forms through Mailbox.send_message
- [x] Remove dead Ash domains
- [ ] Full migration to Claude Code native messaging paths
- [ ] Clean up 164 stale CommandQueue files
- [ ] Add ETS TTL cleanup and ordering guarantees
