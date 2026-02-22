---
id: ADR-012
title: Dual Data Source Architecture (Disk + Events)
date: 2026-02-14
status: accepted
related_tasks: []
parent: null
superseded_by: null
---
# ADR-012 Dual Data Source Architecture (Disk + Events)
[2026-02-14] accepted

## Related ADRs
- [ADR-005](ADR-005-ets-over-database.md) ETS for Messaging over Database
- [ADR-007](ADR-007-swarm-monitor-design.md) SwarmMonitor and ProtocolTracker

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Team Inspector Design | [CONV-003](../conversations/CONV-003-team-inspector.md) | Scout-data discovered dual source shapes during Sprint 1 |
| Swarm Control Center Design | [CONV-001](../conversations/CONV-001-swarm-control-center.md) | TeamWatcher field-dropping rediscovered as critical gap |
| Session JSONL (inspector) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/8585be9e-149a-4133-bed8-ef55dd380dc9.jsonl` | Raw session transcript |
| Session JSONL (control center) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/1f469adb-7830-4fb9-ac26-af6d0b3fbc45.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-14T23:54:11Z | Scout-data: full team data structures analysis, disk vs event member shapes |
| 2026-02-15T00:20:20Z | Architect validation: TeamWatcher drops cwd, model, color, isActive fields |
| 2026-02-21T12:11:39Z | Critical: TeamWatcher drops most useful fields; must be fixed for Swarm Control Center |

## Context

Team state in the Observatory comes from two independent sources:
1. **Disk:** `~/.claude/teams/` config files and `~/.claude/tasks/` directories, polled by TeamWatcher every 2 seconds
2. **Events:** Hook events (SessionStart, PreToolUse, etc.) streamed via PubSub `"events:stream"`

Neither source alone provides a complete picture. Disk has team structure and membership but no runtime state. Events have runtime activity but no team context.

## Decision

Dual data source architecture with disk as authoritative:
- **TeamWatcher** (GenServer) polls disk for team config, membership, and task lists. Disk state is the source of truth for team existence and membership.
- **DashboardTeamHelpers** merges disk data with event-derived runtime data (health, status, model, cwd, current tool, uptime) in `enrich_team_members/3`.
- **Member struct variance:** Disk members use `:agent_id` key, event-derived members use `:session_id`. Code must handle both.
- **Role detection:** No explicit role field on disk members. Derived from team config: first member = lead, or check `agentType` field.

## Rationale

Disk is authoritative because it represents intentional state (user/agent created a team). Events are ephemeral and may arrive out of order or not at all (if agents crash before emitting). Merging in `prepare_assigns()` ensures the view always reflects the latest known state from both sources.

The member struct variance is an accepted consequence of having two data sources with different schemas. Normalizing would require either modifying TeamWatcher output (breaking other consumers) or adding a mapping layer (unnecessary abstraction for a known variance).

## Consequences

- `prepare_assigns()` called from mount and every handle_event/handle_info -- recomputes merged state
- **Performance concern:** `enrich_team_members/3` runs on every 1s tick, creating new list references even when nothing changed. This triggers LiveView re-renders (see form refresh bug, mitigated by `phx-update="ignore"`)
- **Member key access:** Always use `member[:agent_id]` or `member[:session_id]` with bracket syntax (not dot syntax) to handle both shapes
- **Dead team detection:** Cross-reference disk teams with event timestamps to detect teams whose agents have stopped emitting events
