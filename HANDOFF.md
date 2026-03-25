# ICHOR IV - Handoff

## Current Status: DEAD CODE CLEANUP COMPLETE (2026-03-25)

Refactor items 6, 11, 13, 15, 16 + inline AgentLookup executed. All deleted/inlined.
Build clean. 211 tests, 13 failures (all pre-existing, unrelated to this work).

### What Was Done This Session

**Dead code cleanup -- 9 modules deleted, logic inlined at callsites:**

1. **Item 6**: Deleted `SyncRunner` notifier from `PipelineTask.simple_notifiers`. Fragile `Code.ensure_loaded?` + `try/rescue` pattern gone.
2. **Item 11a**: Inlined `WorkStatus` Ash enum type into `RoadmapItem` as `constraints(one_of: [...])`.
3. **Item 11b**: Inlined `HealthStatus` Ash enum type into `Workshop.Agent` attribute.
4. **Item 11c+d**: Inlined `LocationType` and `AuthMethodType` into `SettingsProject.Location`.
5. **Item 12b**: Inlined `AgentLookup` (61 lines) into `Workshop.Agent` as private `spawn_in_fleet/2`, `find_agent/1`, `build_agent_match/3`. Removed public module.
6. **Item 13a**: Inlined `DateUtils.parse_timestamp/1` into both `PipelineGraph` and `PipelineQuery` as private defp.
7. **Item 13b**: Inlined `SessionEviction.evict_stale/2` into `DashboardState` as private `evict_stale/2` + `do_evict_stale/2`.
8. **Item 15**: Replaced `%TeamPreset{...}` bare struct with plain maps in `Presets`. Deleted `TeamPreset` module.
9. **Item 16**: Removed dead public functions:
   - `EntropyTracker`: removed `record_and_score/2`, `register_agent/2`, `get_window/1`, `reset/0` + their `handle_call`/`handle_cast` clauses
   - `EscalationEngine`: removed `clear/2` (dead, `AgentWatchdog` uses `Map.pop` directly)
   - `EventStream`: removed `subscribe/2` and `publish_fact/2` (zero callers)
   - `ProtocolTracker`: removed stale `mailbox: %{total_unread: 0}` and `command_queue: %{total_pending: 0}` from `compute_stats/0`

**Simplify pass fixes:**
- `evict_stale`: replaced `case boolean do` with idiomatic `if`
- `do_evict_stale`: replaced `stale_sids == MapSet.new()` with `MapSet.size(stale_sids) == 0`
- Added missing trailing newline to `pipeline_graph.ex`

### Modules Deleted (moved to tmp/trash/)
- `Ichor.Factory.PipelineTask.Notifiers.SyncRunner`
- `Ichor.Factory.Types.WorkStatus`
- `Ichor.Workshop.Types.HealthStatus`
- `Ichor.Settings.Types.LocationType`
- `Ichor.Settings.Types.AuthMethodType`
- `Ichor.Workshop.AgentLookup`
- `Ichor.Factory.DateUtils`
- `Ichor.Workshop.Analysis.SessionEviction`
- `Ichor.Workshop.Presets.TeamPreset`

### Build Status
- `mix compile --warnings-as-errors`: CLEAN
- `mix test`: 211 tests, 13 failures (all pre-existing -- Ash MustBeAtomic + UUID cast errors)

### Remaining Work (from prior sessions)
- **SIG-7**: Handler behaviour + facade dispatch
- **SIG-8**: Split catalog into catalog/
- **Wave 2**: Entropy handler + SignalManager split
- **Wave 3**: Module relocations
- **Wave 4**: Specs, types, structs
- **ADR-026**: `use Ichor.Signal` macro, `Ichor.Signals.Memories.*` modules
