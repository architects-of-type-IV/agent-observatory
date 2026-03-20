# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents
- **Architect**: the user. **Archon**: AI floor manager. **Operator**: messaging relay.

## Domain Architecture (4 domains, pure declarations now)
- **Ichor.Control** -- 22 LOC, pure `use Ash.Domain` + resources. 9 resources.
- **Ichor.Projects** -- 25 LOC, pure domain declaration. 13 resources.
- **Ichor.Observability** -- ~20 LOC, pure domain declaration. 7 resources.
- **Ichor.Tools** -- MCP surfaces, 21 resources, capability-based with Profiles
- **Signals bus** -- infrastructure/nervous system. Not a domain.
- Callers use resource code_interface directly (`Resource.action!(args)`), never domain wrappers.

## File Structure (215 files, target 60)
- control/ -- agent lifecycle, fleet, workshop, lifecycle/
- projects/ -- genesis planning, MES lifecycle, DAG execution
- observability/ -- events, activity, preparations
- tools/agent/ -- 12 MCP tool resources for agents
- tools/archon/ -- 9 MCP tool resources for archon
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

## Oban Candidates (identified, not yet installed)
- Strong: webhook_router, cron_scheduler, quality_gate, memories ingest, janitor

## User Preferences
- Codex is an equal architectural partner. Give raw data, let it form conclusions.
- All implementation: ash-elixir-expert. Exploration: feature-dev:code-explorer. Cleanup: code-simplifier.
- Commits: background haiku agent. Build/credo/dialyzer: delegated to agents.
- Coordinate and delegate. No direct code edits from coordinator.
- No backward compat. Surgical edits. Frontend must work. Split work evenly by file count.
- Design 80%, code 20%. Plan edits before executing.
- For small tasks: list exact edits in prompt, no exploration freedom.
