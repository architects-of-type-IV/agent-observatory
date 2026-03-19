# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents
- **Architect**: the user. **Archon**: AI floor manager. **Operator**: messaging relay.

## Domain Architecture (4 domains, 2026-03-19)
- **Ichor.Control** -- agents, configs, spawning, webhooks, cron (9 resources)
- **Ichor.Projects** -- planning, coherence, execution (13 resources)
- **Ichor.Observability** -- events, activity, HITL audit (7 resources)
- **Ichor.Tools** -- MCP surfaces, 21 resources, capability-based with Profiles
- **Signals bus** -- infrastructure/nervous system. Not a domain.

## File Structure (post-reorg, 214 files)
- control/ -- 39 modules (agent lifecycle, fleet, workshop)
- projects/ -- 64 modules (genesis planning, MES lifecycle, DAG execution)
- observability/ -- 12 modules (events, activity, preparations)
- tools/agent/ -- 12 MCP tool resources for agents
- tools/archon/ -- 9 MCP tool resources for archon
- gateway/ -- 20 modules (transport infrastructure)
- archon/ -- 13 modules (chat, signal_manager, team_watchdog)
- signals/ -- 7 modules (bus, buffer, catalog, from_ash)
- Infrastructure: memory_store/, mesh/, tasks/, plugs/, architecture/

## Core Principles
- Domain is the ONLY public API. Resources NEVER called directly.
- Ash DSL replaces custom helpers (calculations, aggregates, preparations, generic actions).
- No raw Ecto.Schema/Changeset/Repo (exception: DecisionLog transport envelope).
- Module exists only if it owns: process, framework callback, or multi-caller contract.
- Signals is the nervous system -- mass decoupling and chaining.

## Known Anti-Patterns (from deep audit)
- Domain modules (control.ex, projects.ex) are 100% pass-through wrappers -- should use Ash `define` on resources
- 3 lifecycle GenServers share 60 lines of identical boilerplate
- 3 spawn chains (MES, Genesis, DAG) should converge to Workshop presets
- Spawn links ≠ comm rules (spawn links must be DAG, comm rules can cycle)
- GenesisFormatter.to_map emits signals (impure side effect in projection function)
- Virtual resources with FromAsh notifiers never fire (dead code)

## MES Team Topology (restored to original)
- Coordinator → Lead → (Researcher-1 + Researcher-2 parallel) → Lead → Planner → Lead → Coordinator → Operator
- Lead is ACTIVE DISPATCHER (assigns topics, collects results, forwards to planner)
- Spawn links are a tree (coordinator spawns all). Comm rules are cyclic (message flow).

## Workshop Presets
- 5 presets: dag, solo, research, review, mes
- UI buttons generated from Presets.ui_list/0 (data-driven, not hardcoded)
- MES uses preset as fallback when no DB blueprint named "mes" exists
- Genesis and DAG bypass Workshop entirely (separate spawn chains -- consolidation target)

## Dependency Cycles (5 found via mix xref)
- Control: 14-node compile cycle (biggest problem)
- Projects: 6-node cycle through exporter/health_checker/job/run_process
- Projects lifecycle: 4-node cycle (build_runner/janitor/team_cleanup/team_lifecycle)
- Archon chat: 2-node mutual dependency
- Web: 13-node standard Phoenix router cycle

## User Preferences
- Always consult codex (direct `codex exec --full-auto` for advisory, run.sh for code)
- All implementation agents: ash-elixir-expert. Research agents: code-explorer.
- Coordinate and delegate. No direct code edits from coordinator.
- No backward compat. Surgical edits. Frontend must work. Split work evenly by file count.
- Tests during refactor: delete, don't adapt.
