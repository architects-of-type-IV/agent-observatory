# Team Inspector Feature Design

**Date**: 2026-02-14 to 2026-02-15
**Topic**: Building the Team Inspector view mode with roadmap-driven multi-agent team
**Status**: Complete
**Sessions**:
- `8585be9e-149a-4133-bed8-ef55dd380dc9` (roadmap creation, team coordination lessons)
- `3b9cd554-74a4-46c3-9db6-6d15f99fc615` (architect validation, scout reports)
- `51d2106f-526b-46b2-be46-f1a9b3ada4e1` (UI scout enrichment)

## Referenced ADRs

| ADR | Title | Relevance |
|-----|-------|-----------|
| [ADR-009](../decisions/ADR-009-roadmap-naming.md) | Flat File Roadmaps | Naming convention established during this feature |
| [ADR-011](../decisions/ADR-011-handler-delegation.md) | Handler Delegation | Pattern scaled from 3 to 6 handlers during this feature |
| [ADR-012](../decisions/ADR-012-dual-data-sources.md) | Dual Data Sources | Architecture confirmed during team data analysis |

## Context

Observatory needed a way to inspect running teams -- see member roles, health, task progress, and communicate with agents. This was the first feature built using the 5-level roadmap protocol, making it a test of both the feature AND the multi-agent workflow.

## Research

### Scout Phase (4 parallel agents)

**Scout-data**: Mapped team data structures -- dual sources (disk TeamWatcher + event PubSub), member struct key variance (`:agent_id` vs `:session_id`), missing runtime enrichment fields.

**Scout-messaging**: Full Mailbox struct shape analysis -- plain maps in ETS, dual-write pattern, CommandQueue file format. Confirmed MCP AshAi nesting under `"input"` key.

**Scout-UI**: Cataloged component patterns -- bg-zinc-900 cards, border-zinc-800, text-zinc-300 normal text. Documented Tailwind dark theme color system.

**Scout-integration**: Enriched 2.4.x tasks with exact line numbers and insertion points in dashboard_live.ex.

### Architect Validation

Read all 29 roadmap files, BRAIN.md, and key source files. Identified:
- 6 missing tasks (prepare_assigns updates, keyboard shortcut 9, CSS for drawer)
- 4 changes needed (handler location, safe_atom pattern, event filtering scope)
- 5 risks (member struct variance, format-on-save race, import conflicts)

### Key Discovery: In-Process Agents Cannot Write Files

Spawned teammate agents with `bypassPermissions` mode. They could read files and run bash, but ALL file write/edit tools returned "No such tool available." This was a critical finding that changed the team workflow: implementation work must be done by the lead, with agents used only for research/verification.

## Decisions

| Topic | Decision | Rationale | ADR |
|-------|----------|-----------|-----|
| Roadmap naming | Flat files, dotted numbering, unix timestamps | User explicitly rejected subdirectories | ADR-009 |
| Handler pattern | Scale to 6 domain-specific modules | Pattern holds at scale, non-overlapping scopes | ADR-011 |
| Data architecture | Disk authoritative, events for enrichment | TeamWatcher owns structure, PubSub owns runtime | ADR-012 |
| Inspector drawer | 3-state (collapsed/default/maximized) | Simpler than drag-resize, maximized triggers tmux overlay | -- |
| Message targets | String-based ("team:name", "member:sid") | Simpler for LiveView event payloads than tuples | -- |
| Agent spawn contract | Must SendMessage when done AND when blocked | Prevents silent completion/failure | -- |
| Task ownership | Lead owns all TaskUpdate calls | Avoids keep-track hook conflicts + split ownership | -- |

## Next Steps

- [x] Implement 17/17 roadmap tasks
- [x] Verify with 4-agent verification team
- [x] Dead code audit (parallel with verification)
- [x] Update BRAIN.md with lessons learned
