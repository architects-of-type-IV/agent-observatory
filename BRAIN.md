# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents
- **Architect**: the user. **Archon**: AI floor manager. **Operator**: messaging relay.

## Domain Architecture (4 domains, pure declarations now)
- **Ichor.Control** -- 22 LOC, pure `use Ash.Domain` + resources. 9 resources.
- **Ichor.Projects** -- 25 LOC, pure domain declaration. 13 resources.
- **Ichor.Observability** -- ~20 LOC, pure domain declaration. 7 resources.
- **Ichor.Tools** -- MCP surfaces, 6 consolidated resources (was 21), capability-based with Profiles
  - RuntimeOps (18 actions), AgentMemory (10), ProjectExecution (14), Genesis (18), ArchonMemory
- **Signals bus** -- infrastructure/nervous system. Not a domain.
- Callers use resource code_interface directly (`Resource.action!(args)`), never domain wrappers.

## Message Bus
- **Ichor.Messages.Bus** -- single delivery authority (replaced MessageRouter)
- Located at `lib/ichor/messages/bus.ex`
- `resolve/1` is public (was private `resolve_target/1` in MessageRouter)
- Gateway.Router still has its own private `resolve/1` returning recipient maps (different shape)

## File Structure (195 files, target 60)
- control/ -- agent lifecycle, fleet, workshop, lifecycle/
- projects/ -- genesis planning, MES lifecycle, DAG execution
- observability/ -- events, activity, preparations
- tools/ -- 6 consolidated resources (RuntimeOps, AgentMemory, ProjectExecution, Genesis, ArchonMemory + tools.ex)
- gateway/ -- transport infrastructure
- archon/ -- chat, signal_manager, team_watchdog
- signals/ -- runtime, buffer, catalog, from_ash (Bus merged into Runtime)

## Core Principles
- Ash resources use `code_interface define` -- callers go directly to resource
- Module exists only if it owns: process, framework callback, or multi-caller contract
- Signals is the nervous system
- All teams are equal. Workshop is the single authority for team topology
- TeamLaunch.teardown/1 is the canonical cleanup path for all team types
- Ash.Type.Enum replaced with `:atom` + `one_of` constraint (same storage, no extra module)

## Resolved Anti-Patterns (this session)
- Domain wrappers DONE -- all 3 facades stripped to pure declarations
- Spawn convergence DONE -- DAG + Genesis both use TeamLaunch
- Dead notifier DONE -- removed from virtual Task
- Unsafe atoms DONE -- 14 callsites replaced with explicit maps
- Impure GenesisFormatter DONE -- signal emission removed
- GatewayController Task.start DONE -- direct Signals.emit
- AgentWatchdog crash-on-unpause DONE -- graceful error handling
- validate_config_inclusion DONE -- Tools now true
- ModeRunner DONE -- deleted (zero callers)

## Workshop & Team Topology
- 8 presets: dag, solo, research, review, mes, genesis_a, genesis_b, genesis_c
- UI buttons generated from Presets.ui_list/0 (data-driven)
- Workshop owns topology. Prompt content is flow-specific (prompt_builder function).
- MES coordinator waits for READY handshake before dispatching. No deadline/fallback.
- Scheduler resume triggers immediate tick (no 60s wait).

## Oban (installed, no workers yet)
- SQLite-compatible, 5 queues: webhooks:10, quality_gate:4, memories:2, maintenance:1, scheduled:2
- Strong migration candidates: webhook_router, cron_scheduler, quality_gate, memories ingest, janitor

## Unified Runner
- One GenServer: `Ichor.Projects.Runner` with data-driven `%Mode{}` config
- MES/Genesis/DAG are mode configs, not separate process stacks
- Hooks for truly different behavior: MES (quality gate, corrective agents), DAG (health, stale jobs)
- Genesis is purely config-driven (no hooks)

## MemoryStore (consolidated)
- 3 modules: MemoryStore (GenServer), Storage (ETS ops), Persistence (disk I/O)
- 5 bugs fixed: block delete dirtying, archival rewrite, load order, DateTime parsing, signal centralization

## Reduction Progress
- Level 1+2 DONE (Session 4): 195→~163 files
  - 23 child modules folded into parents
  - 9 Ash resources collapsed: 5 artifacts→1 `Artifact` (kind discriminator), 4 roadmap→1 `RoadmapItem` (kind + parent_id)
  - decision_log embedded schemas→maps
  - Tables: `genesis_artifacts`, `genesis_roadmap_items` created via manual migration
- Level 3 (next): 4 workshop blueprint resources → 1 embedded blueprint model; more GenServer→ETS demotions

## Migration Lessons (Session 4)
- `mix ash.codegen` with NO prior snapshots generates a "create everything" migration -> WRONG for partial-state DBs
- Correct fix: trash the bad migration, write manual DDL for only the new tables, apply with `mix ecto.migrate`
- Resource snapshots now exist for all resources in `priv/resource_snapshots/repo/`
- `mix ash.migrate` silently skips; use `mix ecto.migrate` for reliable apply

## User Preferences
- Codex is an equal architectural partner. Give raw data, let it form conclusions.
- All implementation: ash-elixir-expert. Exploration: feature-dev:code-explorer. Cleanup: code-simplifier.
- Commits: background haiku agent. Build/credo/dialyzer: delegated to agents.
- Coordinate and delegate. No direct code edits from coordinator.
- No backward compat. Surgical edits. Frontend must work. Split work evenly by file count.
- Design 80%, code 20%. Plan edits before executing.
- For small tasks: list exact edits in prompt, no exploration freedom.
