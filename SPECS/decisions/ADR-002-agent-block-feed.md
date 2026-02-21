---
id: ADR-002
title: Feed Restructured from Event Stream to Agent Blocks
date: 2026-02-21
status: accepted
related_tasks: []
parent: null
superseded_by: null
---
# ADR-002 Feed Restructured from Event Stream to Agent Blocks
[2026-02-21] accepted

## Related ADRs
- [ADR-001](ADR-001-swarm-control-center-nav.md) Swarm Control Center Navigation
- [ADR-003](ADR-003-unified-control-plane.md) Unified Control Plane

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Swarm Control Center Design | [CONV-001](../conversations/CONV-001-swarm-control-center.md) | Feed redesign discussed within broader control center design |
| Session JSONL | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/1f469adb-7830-4fb9-ac26-af6d0b3fbc45.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-21T12:45:07Z | User: "blocks of agents, each its own feed. Agent name, session, metadata, timestamps, clear start stop indicators." |
| 2026-02-21T12:47:55Z | Implementation decision: agent-block grouping with hierarchy |
| 2026-02-21T12:53:44Z | User: "Task agents with tool calls etc. Each need to be visible as group within the session group." |

## Context

Feed view showed a flat chronological event stream. With multiple agents running simultaneously, events from different agents interleaved freely, making it impossible to follow any single agent's work. The SubagentStart/SubagentStop event model (subagent events fire on the PARENT session_id, subagents do NOT get separate UUIDs) made flat rendering even more confusing.

## Options Considered

1. **Flat event stream with color-coded agent badges** -- Quick to implement, still hard to follow when 5+ agents interleave.
2. **Agent-block grouping with nested subagent hierarchy** -- Each session is a collapsible block with metadata header, subagents nested inside parent blocks. Tool executions grouped into collapsible chains.
3. **Tabbed per-agent feeds** -- Clean separation but loses cross-agent timeline context.

## Decision

Agent-block grouping (option 2). Each session becomes a collapsible block with header showing:
- Agent name (cross-referenced from team member data)
- Session ID, model, cwd, permission mode
- Role (`:lead`, `:worker`, `:relay`, `:standalone`)
- Start/stop timestamps with clear indicators

SubagentStart/SubagentStop events create nested child blocks within parent sessions. Tool executions grouped into collapsible `{:tool_chain, pairs}` tuples via `build_segment_timeline/2`.

## Rationale

Operators think in terms of agents, not events. A block per agent with its own sub-feed preserves temporal context while making individual agent activity scannable. Nesting subagents under parents reflects the actual execution hierarchy (parent spawns child via Task tool).

The user's explicit request drove this: they wanted metadata, timestamps, and clear start/stop indicators -- information that only makes sense at the agent level, not the event level.

## Consequences

- `build_feed_groups/2` now accepts teams list for agent name cross-referencing
- Role detection per session: `:lead`, `:worker`, `:relay`, `:standalone`
- `build_segment_timeline/2` interleaves tool pairs + standalone events chronologically
- Consecutive tools grouped into `{:tool_chain, pairs}` tuples
- Recursive ToolChain component: multi-tool chains render single-tool children via same component
- Feed segments: `:parent` (direct events) and `:subagent` (bracketed by Start/Stop)
- Parallel subagents: events in overlapping time ranges appear in both blocks
