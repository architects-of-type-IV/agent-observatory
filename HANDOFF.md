# ICHOR IV - Handoff

## Current Status: Session 4 -- Domain Facade Removal (2026-03-20)

### Session Summary

Deleted all 31 pass-through wrapper functions from `Ichor.Control` (the domain facade).
Resources already had `define` in their `code_interface` — callers now use resource interfaces directly.

### What Was Done This Session

1. **Pre-requisite added** — `TeamBlueprint.list_with_relationships` read action + code_interface define.
   Before: `list_blueprints/0` wrapper called `TeamBlueprint.read!(load: [...])` with a runtime load option.
   After: named action encodes the load, callers call `TeamBlueprint.list_with_relationships!()`.

2. **Facade stripped** — `lib/ichor/control.ex` reduced from 169 LOC to 22 LOC. Only `use Ash.Domain` and `resources do` block remain. All 31 wrapper functions deleted.

3. **Callers migrated (9 files):**
   - `lib/ichor/control/lookup.ex` → `Agent.all!()`
   - `lib/ichor/control/persistence.ex` → `TeamBlueprint.{by_id,create,update,destroy}`
   - `lib/ichor/gateway/cron_scheduler.ex` → `CronJob.{for_agent!,all_scheduled!,schedule_once,get,complete,reschedule}`
   - `lib/ichor/gateway/webhook_router.ex` → `WebhookDelivery.{enqueue,due_for_delivery!,...}`
   - `lib/ichor_web/controllers/debug_controller.ex` → `Agent.all!(), Team.alive!()`
   - `lib/ichor_web/live/dashboard_state.ex` → `Agent.all!(), Team.{alive!,all!}`
   - `lib/ichor_web/live/dashboard_workshop_handlers.ex` → `TeamBlueprint.list_with_relationships!(), AgentType.*`
   - `lib/ichor_web/live/workshop_persistence.ex` → `TeamBlueprint.list_with_relationships!(), AgentType.sorted!()`
   - `lib/ichor_web/live/workshop_types.ex` → `AgentType.{by_id,create,update,destroy,sorted!}`
   - `lib/ichor/projects/team_spec_builder.ex` → `TeamBlueprint.by_name`

4. **Pre-existing issues fixed:**
   - `spawner.ex`: `Node` alias shadowing Elixir built-in → `ProjectNode`
   - `dashboard_mes_handlers.ex`: same Node alias issue → `ProjectNode`
   - `exporter.ex`: inline full module ref → `Job` alias
   - `dashboard_state.ex`: alias ordering

### Build Status
- `mix compile --warnings-as-errors` — CLEAN
- `mix credo --strict` — CLEAN (0 issues)
- Git: clean on main

### Active Plan
- `~/.claude/plans/tender-giggling-nebula.md` — Phase 6 (Domain Wrapper Removal) is now COMPLETE
- Next phases: Per plan, Phase 5 (Safety sweep) was last remaining

### Key Architectural Decisions
- All teams are equal. Workshop is the single authority for team topology.
- Ash resources use `code_interface define` — callers go directly to resource, never through a domain facade.
- `Ichor.Control` is now a pure Ash.Domain declaration (resources only).
- Codex is an equal partner, not a validator. Give it raw data, let it form conclusions.
- RunnerRegistry is the canonical registry boilerplate helper for all runner GenServers.

### Key Files
- `lib/ichor/control.ex` — stripped to domain declaration only (22 LOC)
- `lib/ichor/control/team_blueprint.ex` — new `list_with_relationships` action
- `~/.claude/plans/tender-giggling-nebula.md` — session 3 plan (codex-reviewed)
