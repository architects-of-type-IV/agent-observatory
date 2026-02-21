---
id: ADR-003
title: Three-Tab Merge into Unified Control Plane
date: 2026-02-21
status: accepted
related_tasks: []
parent: ADR-001
superseded_by: null
---
# ADR-003 Three-Tab Merge into Unified Control Plane
[2026-02-21] accepted

## Related ADRs
- [ADR-001](ADR-001-swarm-control-center-nav.md) Swarm Control Center Navigation (parent)
- [ADR-002](ADR-002-agent-block-feed.md) Agent Block Feed

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Swarm Control Center Design | [CONV-001](../conversations/CONV-001-swarm-control-center.md) | Tab merge requested during control center iteration |
| Session JSONL | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/1f469adb-7830-4fb9-ac26-af6d0b3fbc45.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-21T12:53:44Z | User: "Can you join the first 3 tabs into one overview." |
| 2026-02-21T14:29:51Z | User: "pages that could all be integrated into the dashboard overviews" |

## Context

After implementing the Swarm Control Center nav restructure (ADR-001), the dashboard had separate Command, Pipeline, and Agents views as the first three tabs. The user observed that for operational use, switching between these tabs broke the flow -- all three answer the same meta-question: "what is happening right now?"

## Options Considered

1. **Keep as 3 separate tabs** -- Cleaner separation of concerns but requires tab-switching for situational awareness.
2. **Stack all 3 as sections in one view with collapsible sidebar** -- Single-page control plane. Sidebar provides quick-jump navigation within stacked sections.

## Decision

Unified control plane. The Command view stacks agent grid, health bar, pipeline progress, and agents into a single scrollable view with a collapsible sidebar for section navigation.

## Rationale

For a swarm operator, the key information (agent status, pipeline progress, health) should all be visible without switching tabs. Tab-switching for tightly related data adds cognitive overhead. The collapsible sidebar reduces horizontal space when the operator knows where they are.

## Consequences

- Single `:command` view mode handles all three operational concerns
- Collapsible sidebar provides section-level navigation within the view
- CommandComponents renders stacked sections: agent grid, health, pipeline, agents
- Commit `150e762`: "feat(overview): unified control plane with collapsible sidebar"
- Other views (Feed, Errors, Protocols) remain separate tabs for focused work
