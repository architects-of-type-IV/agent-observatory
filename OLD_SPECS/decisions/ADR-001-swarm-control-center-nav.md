---
id: ADR-001
title: Swarm Control Center Navigation Restructure
date: 2026-02-21
status: accepted
related_tasks: []
parent: null
superseded_by: null
---
# ADR-001 Swarm Control Center Navigation Restructure
[2026-02-21] accepted

## Related ADRs
- [ADR-003](ADR-003-unified-control-plane.md) Unified Control Plane
- [ADR-004](ADR-004-messaging-architecture.md) Messaging Architecture

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Swarm Control Center Design | [CONV-001](../conversations/CONV-001-swarm-control-center.md) | Full design conversation: codebase analysis, UX critique, plan approval |
| Session JSONL | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/1f469adb-7830-4fb9-ac26-af6d0b3fbc45.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-21T12:01:05Z | Initial analysis: dashboard is feed-centric, missing agent control |
| 2026-02-21T12:13:10Z | UX analysis: "built by feature accumulation" |
| 2026-02-21T12:15:50Z | Plan approved: Command/Pipeline/Agents/Protocols/Feed/Errors/More |

## Context

The Observatory dashboard had 9 equal-weight tabs (Feed, Tasks, Messages, Agents, Agent Focus, Errors, Analytics, Timeline, Teams). No clear operational hierarchy existed. A swarm operator couldn't answer "what's happening now?" without clicking through multiple views. UX analysis concluded the dashboard was "built by feature accumulation rather than designing for a workflow."

## Options Considered

1. **Keep all 9 tabs, improve each** -- Maintains familiarity but doesn't solve information architecture problem. Operator still clicks through N tabs to get situational awareness.
2. **Collapse to 4 primary + 3 overflow** -- Clear operational hierarchy with "command cockpit" metaphor. Primary tabs answer operator questions in priority order.
3. **Single scrollable dashboard** -- Too dense, no focus. Tried and rejected in the same session.

## Decision

Collapse from 9 tabs to 7 with clear hierarchy:
- **Primary (4):** Command (default), Pipeline, Agents, Protocols
- **Standard (2):** Feed, Errors
- **Overflow dropdown (2+):** Analytics, Timeline

Teams merged into Agents (80% duplicate data). Analytics and Timeline demoted to "More" dropdown -- not deleted, just not primary.

## Rationale

Operators need context before data. Command view as default provides agent grid + health bar + pipeline progress + alerts -- answers "do I need to intervene?" at a glance. Previous defaults (:feed, then :overview) forced operators to navigate before understanding state.

The merge of Teams into Agents was driven by observing that ~80% of the data in both views overlapped. Team membership is a property of agents, not a separate entity.

## Consequences

- Default `view_mode` changed from `:overview` to `:command`
- Two new GenServers required: SwarmMonitor (pipeline data), ProtocolTracker (message tracing)
- Keyboard shortcuts 1-7 remapped to new tab order
- Old `:overview` atom persisted in localStorage breaks gracefully (rescue -> default)
- New component modules: CommandComponents, PipelineComponents, ProtocolComponents
