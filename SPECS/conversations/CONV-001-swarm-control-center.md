# Swarm Control Center Design Conversation

**Date**: 2026-02-21
**Topic**: Transforming Observatory from feed-viewer into operational swarm cockpit
**Status**: Complete
**Session**: `1f469adb-7830-4fb9-ac26-af6d0b3fbc45`

## Referenced ADRs

| ADR | Title | Relevance |
|-----|-------|-----------|
| [ADR-001](../decisions/ADR-001-swarm-control-center-nav.md) | Nav Restructure | Primary outcome -- 9 tabs to 7 |
| [ADR-002](../decisions/ADR-002-agent-block-feed.md) | Agent Block Feed | Feed redesign to agent-grouped blocks |
| [ADR-003](../decisions/ADR-003-unified-control-plane.md) | Unified Control Plane | Merging first 3 tabs into one overview |
| [ADR-007](../decisions/ADR-007-swarm-monitor-design.md) | SwarmMonitor Design | New GenServers backing the control center |
| [ADR-008](../decisions/ADR-008-default-view-evolution.md) | Default View Evolution | :command as default view mode |
| [ADR-010](../decisions/ADR-010-component-file-split.md) | Component File Split | embed_templates pattern for new components |

## Context

User has existing `/dag` and `/swarm` skills for autonomous multi-agent pipelines. The Observatory dashboard exists but is feed-centric -- 9 equal-weight tabs with no operational hierarchy. User wants "full insights/overview/control over what the swarm is doing, their agents, sessions etc."

## Research

### Codebase Analysis (4 parallel explorer agents)
- **Architecture explorer**: Mapped the full Phoenix LiveView app -- single route, 10 view modes, 6 handler modules, 5 GenServers
- **Swarm/DAG explorer**: Mapped the skill infrastructure -- tasks.jsonl, health-check.sh, claim/complete scripts, tmux session management
- **UI pattern explorer**: Cataloged component patterns, Tailwind dark theme, keyboard shortcuts, view mode switching
- **UX critic**: Diagnosed information architecture -- "dashboard built by accumulating features rather than designing for a workflow"

### Critical Findings
1. **TeamWatcher drops most useful fields** -- `cwd`, `model`, `isActive`, `tmuxPaneId`, `color`, `joinedAt` all parsed then discarded
2. **tasks.jsonl never read** -- TeamWatcher reads `~/.claude/tasks/{team}/` (always empty) but real task state lives at `{project_root}/tasks.jsonl`
3. **No project-level grouping** -- teams have no `cwd`/`project` field; must infer from members

### Design Approach
Operational cockpit metaphor: primary tabs answer operator questions in priority order:
- Command: "Do I need to intervene?" (agent grid, health, pipeline status)
- Pipeline: "What's the work state?" (DAG visualization, task table)
- Protocols: "How are agents communicating?" (message traces across 4 channels)

## Decisions

| Topic | Decision | Rationale | ADR |
|-------|----------|-----------|-----|
| Tab structure | 4 primary + 2 standard + overflow | Operational hierarchy over feature parity | ADR-001 |
| Default view | `:command` (not `:overview` or `:feed`) | Action-centric: "what needs attention" | ADR-008 |
| Teams view | Merged into Agents | 80% data overlap with Agents view | ADR-001 |
| Feed rendering | Agent blocks with nested subagent hierarchy | User: "blocks of agents, each its own feed" | ADR-002 |
| Tab merge | First 3 tabs into one unified control plane | User: "join the first 3 tabs into one overview" | ADR-003 |
| Backend services | SwarmMonitor + ProtocolTracker GenServers | Pipeline state from tasks.jsonl + protocol tracing | ADR-007 |
| Large components | .ex + .heex split via embed_templates | Module size limit (200-300 lines) | ADR-010 |

## Next Steps

- [x] Fix TeamWatcher field preservation
- [x] Create SwarmMonitor and ProtocolTracker GenServers
- [x] Build CommandComponents, PipelineComponents, ProtocolComponents
- [x] Rewrite feed as agent-block hierarchy
- [x] Split large components into .ex + .heex
- [x] Unify first 3 tabs into collapsible sidebar control plane
- [ ] Wire SwarmMonitor actions (heal, reassign, GC) to live buttons
- [ ] Connect ProtocolTracker to actual message channel tracing
