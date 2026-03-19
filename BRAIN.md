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

## File Structure (post-reorg + extraction, ~225 files)
- control/ -- 39 modules (agent lifecycle, fleet, workshop)
- projects/ -- 64 modules (genesis planning, MES lifecycle, DAG execution)
- observability/ -- 12 modules (events, activity, preparations)
- tools/agent/ -- 12 MCP tool resources for agents
- tools/archon/ -- 9 MCP tool resources for archon
- gateway/ -- 24 modules (transport infrastructure)
- archon/ -- 11 modules (chat, signal_manager, team_watchdog)
- signals/ -- 9 modules (bus, buffer, catalog, from_ash)
- mesh/ -- includes causal_dag/, decision_log/ subdirs (extracted nested modules)
- Infrastructure: memory_store/, tasks/, plugs/, architecture/

## Core Principles
- Domain is the ONLY public API. Resources NEVER called directly.
- Ash DSL replaces custom helpers (calculations, aggregates, preparations, generic actions).
- No raw Ecto.Schema/Changeset/Repo (exception: DecisionLog transport envelope).
- Module exists only if it owns: process, framework callback, or multi-caller contract.
- One module per file. No nested defmodule.
- Signals is the nervous system -- mass decoupling and chaining.
- All teams are equal. Workshop is the single authority for team topology.

## Known Anti-Patterns (from deep audit + codex review)
- Domain modules (control.ex, projects.ex) are 100% pass-through wrappers -- should use Ash `define`
- 3 lifecycle GenServers share boilerplate but are NOT structurally equivalent (BuildRunner differs)
- 3 spawn chains (MES, Genesis, DAG) should converge to Workshop presets + TeamLaunch
- GenesisFormatter.to_map emits signals (impure side effect)
- Virtual Task resource with FromAsh notifier = dead code
- RunProcess async Task.start for file writes contradicts Exporter's serialized contract
- validate_config_inclusion? still false on Tools domain
- Task.start wrapping synchronous Signals.emit in GatewayController = latent bug

## Workshop & Team Topology
- 5 presets: dag, solo, research, review, mes (Genesis presets needed)
- UI buttons generated from Presets.ui_list/0 (data-driven)
- MES uses preset as fallback when no DB blueprint named "mes" exists
- Workshop owns topology. Prompt content is flow-specific (prompt_builder function).
- Spawn links are a tree (coordinator spawns all). Comm rules are cyclic (message flow).

## Oban Candidates (identified, not yet installed)
- Strong: webhook_router, cron_scheduler, quality_gate, memories ingest, janitor
- Maybe: run_process file sync, memories_bridge flush, watchdog notifications
- Bugs: gateway_controller Task.start wrapping synchronous Signals.emit

## User Preferences
- Codex is an equal architectural partner. Give raw data, let it form conclusions.
- All implementation: ash-elixir-expert. Exploration: feature-dev:code-explorer. Cleanup: code-simplifier.
- Commits: background haiku agent. Build/credo/dialyzer: delegated to agents.
- Coordinate and delegate. No direct code edits from coordinator.
- No backward compat. Surgical edits. Frontend must work. Split work evenly by file count.
- Tests during refactor: delete, don't adapt.
- Design 80%, code 20%. Plan edits before executing.
