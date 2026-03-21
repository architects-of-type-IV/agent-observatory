# ICHOR IV - Handoff

## Current Status: Ash Idiomacy Audit + Dead Code Cleanup (2026-03-21)

### Summary
Two audits completed in one session: (1) Ash Domains & Resources idiomacy audit across all 5 domains/33 resources, (2) Frontend dead code removal. Build clean. Migration applied.

### What Was Done

#### Ash Idiomacy Audit (16 high findings fixed)
1. SyncPipelineProcess after_action -> Ash.Notifier (new: `notifiers/sync_runner.ex`)
2. Pipeline `task_count` stored attribute removed (computed from tasks, migration applied)
3. Pipeline `get_run_status` refactored to compute stats from tasks (AshSqlite doesn't support aggregates)
4. Project.ex `Signals.emit` removed from action bodies (TODO for notifier -- artifact IDs not available in notification)
5. `Ash.read!()` -> `Ash.read()` with error handling in Agent, ActiveTeam
6. `allow_nil?: false` with defaults added to all tool arguments (OpenAI schema compat)
7. Private helpers extracted from Agent resource -> `AgentLookup` utility module
8. Missing error clauses added to AgentMemory
9. LoadAgents health changed from hardcoded `:healthy` to `:unknown`
10. LoadAgents `:paused -> :idle` mapping documented
11. ToolFailure deduplicated (uses code interface instead of duplicated load logic)
12. Redundant code removed (WebhookDelivery set_attribute, Operations fallbacks)
13. `require_atomic?(false)` removed where no fn-based changes exist
14. Consistent argument access patterns (input.arguments.field)
15. `allow_nil?(false)` added to 6 agent_type attributes with defaults

#### Frontend Dead Code Removal
1. 8 dead files removed (7 modules + 1 template)
2. Dead delegates removed from FeedComponents, IchorComponents
3. Dead functions removed from FleetHelpers (7 public + 4 private), MesStatusComponents, DashboardUIHandlers, DashboardMessagingHandlers
4. `resolve/1` made private in DashboardViewRouter

### Build
- `mix compile`: 0 new warnings, 0 errors (8 pre-existing redefining-module from ichor_contracts)
- Migration `20260321024007` applied (removed task_count from pipelines)

### Key Discovery
- AshSqlite does not support `{:aggregate_relationship, _}` -- aggregates block cannot be used with SQLite data layer
- SQLite cannot ALTER COLUMN (NOT NULL constraint changes require table recreation)

### File Count: ~127 (+ 2 new, - 9 deleted)

### Next
- Commit these changes
- Continue redesign toward ~55 files (vertical slices + Ash domains)
- Oban worker migration (5 strong candidates)
- ichor_contracts cleanup (stale beam files causing redefining-module warnings)
