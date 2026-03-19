# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents
- **Architect**: the user. **Archon**: AI floor manager. **Operator**: messaging relay.

## Domain Architecture (4 domains, consolidated 2026-03-19)
- **Ichor.Control** -- agents, configs, spawning, webhooks, cron. Fleet = all agents. Team = group filter.
- **Ichor.Projects** -- project lifecycle. Genesis = planning. DAG = coherence (waves). MES = lifecycle.
- **Ichor.Observability** -- events, activity, HITL audit trail. Everything that happened.
- **Ichor.Tools** -- unified MCP surfaces. 21 resources. Capability-based, scoped per endpoint.
- **Signals bus** -- infrastructure. emit/subscribe/Message/Buffer/Catalog. Not a domain.

## Ash Rules
- Domain is the ONLY public API. Resources NEVER called directly.
- `validate_config_inclusion?` enabled on all domains.
- Resources don't need data sources -- action-only resources valid.
- Use Ash DSL (calculations, aggregates, preparations, generic actions) not custom helpers.
- Ash.Type.Enum for finite value sets (7 extracted).
- No raw Ecto.Schema/Changeset/Repo -- use Ash Resources. Exception: DecisionLog (non-persisted transport envelope).

## AshAi Tool Scoping
- Router `tools:` whitelist is primary scoping mechanism.
- `Ash.can?` policies for actor-based filtering (silent tool hiding).
- Extract profiles to `Ichor.Tools.Profiles` module (agent/0, archon/0).
- `/mcp/archon` endpoint needed for Archon tool access.

## Signal-First Architecture
- ALL meaningful actions emit Signal via FromAsh notifier.
- Buffer stores `{seq, %Message{}}`. LiveView uses streams (at: 0, limit: 200).
- Per-category renderer components. EntryFormatter removed from hot path.

## Performance
- LiveView Streams for real-time feeds. No Task.async per signal.
- Push filters into ETS. Single-pass Enum. Stream over Enum on hot paths.

## Consolidation Heuristics
- Same data shape = same module. Single caller = private function.
- Ash DSL replaces most helper modules.
- Module justifies existence by owning: process, framework callback, or multi-caller contract.

## Constraints
- Module limit: 200L. @enforce_keys, @type t on structs.
- credo --strict clean. Zero warnings. No banners. No backward compat.
- All edits surgical. Frontend must work. Split work evenly across agents.

## User Preferences
- Always consult codex for architecture decisions
- All agents must be ash-elixir-expert
- Coordinate and delegate -- don't code directly
- Signals is the nervous system -- mass decoupling and chaining
- Resources always need a domain, never called directly
