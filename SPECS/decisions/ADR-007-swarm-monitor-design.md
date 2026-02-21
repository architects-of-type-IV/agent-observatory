---
id: ADR-007
title: SwarmMonitor and ProtocolTracker GenServer Design
date: 2026-02-21
status: accepted
related_tasks: []
parent: ADR-001
superseded_by: null
---
# ADR-007 SwarmMonitor and ProtocolTracker GenServer Design
[2026-02-21] accepted

## Related ADRs
- [ADR-001](ADR-001-swarm-control-center-nav.md) Swarm Control Center Navigation (parent)
- [ADR-005](ADR-005-ets-over-database.md) ETS for Messaging over Database

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Swarm Control Center Design | [CONV-001](../conversations/CONV-001-swarm-control-center.md) | GenServer design emerged from TeamWatcher gap analysis |
| Session JSONL | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/1f469adb-7830-4fb9-ac26-af6d0b3fbc45.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-21T12:11:39Z | Critical: tasks.jsonl never read; derive project root from member cwd |
| 2026-02-21T12:15:50Z | Plan: SwarmMonitor reads tasks.jsonl, ProtocolTracker traces messages |
| 2026-02-21T12:18:20Z | SwarmMonitor created at lib/observatory/swarm_monitor.ex |

## Context

The Swarm Control Center (ADR-001) required backend services to provide:
1. **Pipeline state** from actual `tasks.jsonl` files in project roots
2. **Health checks** on running agents and stale tasks
3. **Operational actions** (heal, reassign, GC) from the dashboard
4. **Protocol tracing** across all 4 communication channels (HTTP, PubSub, Mailbox, CommandQueue)

TeamWatcher polled `~/.claude/teams/` and `~/.claude/tasks/` but never read `tasks.jsonl` -- the actual task state for DAG/swarm pipelines.

## Decision

Two new GenServers:

### SwarmMonitor
- Discovers projects by reading team member `cwd` fields from `~/.claude/teams/*/config.json`
- Reads `tasks.jsonl` from discovered project roots
- Computes DAG health: task status distribution, stale detection, blocked chains
- Exposes actions: reassign stale tasks, GC completed teams, heal stuck pipelines
- Broadcasts to `"swarm:update"` PubSub topic

### ProtocolTracker
- Subscribes to `"events:stream"` PubSub topic
- Traces messages across HTTP (webhook events), PubSub (broadcast), Mailbox (ETS), CommandQueue (filesystem)
- Correlates message flows by session_id and timestamp
- Broadcasts to `"protocols:update"` PubSub topic

## Rationale

Project discovery via member `cwd` is the only reliable way to find `tasks.jsonl` without hardcoding paths. Team config already contains the working directory of each member -- following that path to find the project root (and its tasks.jsonl) is a natural derivation.

Separate GenServers (not merged into TeamWatcher) because:
- Different polling intervals (SwarmMonitor needs faster cycles for health detection)
- Different data sources (SwarmMonitor reads files, ProtocolTracker reads events)
- Single responsibility: TeamWatcher owns team config, SwarmMonitor owns pipeline state, ProtocolTracker owns message flows

## Consequences

- Two new supervised processes in `application.ex`
- PubSub topics: `"swarm:update"`, `"protocols:update"` (new)
- Dashboard subscribes to both in mount() for real-time updates
- SwarmMonitor can execute shell commands (health-check.sh) for deep health assessment
- ProtocolTracker provides the data for the Protocols view (ADR-001)
