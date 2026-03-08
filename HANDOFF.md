# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Ash-Disciplined Refactor (Phases 1-5, 7 Complete) (2026-03-08)

### Just Completed: Ash-Disciplined Refactor

Executed 6 of 8 phases from the approved refactor plan. Net -730 lines from web layer, domain logic moved into Fleet/Activity modules.

**Phase 1: Dead Code Deletion**
- Removed 5 functions from DashboardDataHelpers (derive_tasks, derive_messages, active_sessions, extract_errors, group_errors)
- Removed 2 functions from DashboardTeamHelpers (enrich_team_members, detect_dead_teams)
- Removed 2 functions from DashboardSessionHelpers (extract_session_model, extract_session_cwd)

**Phase 2: Role Classification Canonicalization**
- `AgentRegistry.derive_role/1` promoted to public (single source of truth)
- `FleetHelpers.classify_role/1` and `DashboardTeamHelpers.detect_role/2` delegate to it

**Phase 3: Unified Agent Index**
- Added 5 attributes to Fleet.Agent: session_id, short_name, host, channels, last_event_at
- Added `merge_with_registry/2` step to LoadAgents preparation
- DashboardState uses `Fleet.Agent.all!()` + thin `build_agent_lookup/1` (replaces 100-line build_agent_index)

**Phase 4: Sessions/Inspector/Topology Extraction**
- Created `Observatory.Fleet.Queries` module with `active_sessions/2`, `inspector_events/2`, `topology/3`
- Removed ~170 lines from DashboardState

**Phase 5: EventAnalysis**
- Created `Observatory.Activity.EventAnalysis` with `tool_analytics/1`, `timeline/1`, `pair_tool_events/1`
- Removed `compute_tool_analytics` from DashboardDataHelpers
- DashboardTimelineHelpers delegates `compute_timeline_data` to EventAnalysis

**Phase 7: Template Layer Violations Fixed**
- Moved `HITLRelay.paused_sessions()` and `Mailbox.all_messages(50)` from heex to DashboardState assigns

### Remaining Phases
- **Phase 6**: EventController business logic extraction (higher risk, critical event pipeline)
- **Phase 8**: ICHOR IV rename (each rename should be own commit per plan)

### Key New Files
- `lib/observatory/fleet/queries.ex` -- Fleet query functions (sessions, inspector, topology)
- `lib/observatory/activity/event_analysis.ex` -- Tool analytics, timeline, tool event pairing

### Build Status
`mix compile --warnings-as-errors` clean.
