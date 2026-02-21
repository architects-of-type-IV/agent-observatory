---
id: ADR-008
title: Default View Mode Evolution
date: 2026-02-21
status: accepted
related_tasks: []
parent: null
superseded_by: null
---
# ADR-008 Default View Mode Evolution
[2026-02-21] accepted

## Related ADRs
- [ADR-001](ADR-001-swarm-control-center-nav.md) Swarm Control Center Navigation
- [ADR-003](ADR-003-unified-control-plane.md) Unified Control Plane

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Team Inspector Design | [CONV-003](../conversations/CONV-003-team-inspector.md) | :feed -> :overview change during Sprint 3-4 |
| Swarm Control Center Design | [CONV-001](../conversations/CONV-001-swarm-control-center.md) | :overview -> :command change during control center redesign |
| Session JSONL (inspector) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/8585be9e-149a-4133-bed8-ef55dd380dc9.jsonl` | Raw session transcript |
| Session JSONL (control center) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/1f469adb-7830-4fb9-ac26-af6d0b3fbc45.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-15 | Sprint 3-4: :feed -> :overview -- "users need context before raw event streams" |
| 2026-02-21T12:15:50Z | :overview -> :command -- "operational cockpit" metaphor |
| 2026-02-21T12:25:02Z | Old atoms in localStorage handled gracefully via rescue |

## Context

The default view mode determines what operators see on first load. This decision was revisited three times as understanding of operator needs deepened.

## Evolution

### Phase 1: `:feed` (initial, 2026-02-14)
Raw event stream as default. Assumed operators want to see everything happening in real-time.

**Problem:** Information overload. No context for what events mean. Operators had to mentally reconstruct agent state from individual events.

### Phase 2: `:overview` (Sprint 3-4, 2026-02-15)
Statistics and recent activity summary. Provides context before data.

**Problem:** Overview showed aggregate numbers (event counts, active sessions) but didn't answer operational questions. "5 agents active" doesn't tell you if any are stuck.

### Phase 3: `:command` (Sprint 6, 2026-02-21)
Unified control plane. Agent grid + health bar + pipeline progress + alerts. Answers "do I need to intervene?" at a glance.

## Decision

`:command` as the default view mode. Each iteration reflected a deeper understanding:
- `:feed` -- "show me everything" (data-centric)
- `:overview` -- "show me summaries" (context-centric)
- `:command` -- "show me what needs attention" (action-centric)

## Rationale

The progression follows a natural maturation from "monitoring" to "operating." A swarm operator's first question is not "what happened?" (feed) or "how many?" (overview) but "is everything healthy, and if not, where?" (command).

## Consequences

- Default atom `:command` set in `mount/3`
- localStorage may contain stale `:overview` or `:feed` -- handled by `String.to_existing_atom/1` rescue falling through to default
- New users immediately see the most operationally useful view
- Power users can still navigate to Feed or other views via keyboard shortcuts
