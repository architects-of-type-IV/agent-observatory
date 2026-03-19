# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents
- **Architect**: the user. **Archon**: AI floor manager. **Operator**: messaging relay.

## Domain Architecture (consolidated 2026-03-19)
- **Ichor.Control** -- agents, configs, spawning. Fleet = all agents. Team = group filter. Blueprint = config.
- **Ichor.Projects** -- project lifecycle. Genesis = planning. DAG = coherence (waves). MES = lifecycle container.
- **Ichor.Observability** -- events, activity projections, signal queries. Everything that happened.
- **Ichor.Tools** (pending) -- MCP surfaces. Capability-based, not actor-based. Scoped endpoints.
- **Signals bus** -- infrastructure/nervous system. Not a domain. emit/subscribe/Message/Buffer/Catalog.

## Ash Domain Rules
- Domain is the ONLY public API. Resources NEVER called directly.
- All callers go through domain code_interface.
- `validate_config_inclusion?` enabled (compile-time domain/resource alignment check).
- Resources don't need data sources -- action-only resources are valid.
- Ash.Type.Enum for finite value sets (5 extracted, 6 remaining).
- Use calculations, aggregates, preparations, generic actions -- not custom helper modules.

## Signal-First Architecture
- ALL meaningful actions emit a Signal via FromAsh notifier (13 resources).
- `%Message{}` is the canonical envelope (from ichor_contracts).
- Buffer stores `{seq, %Message{}}` tuples. LiveView uses streams (at: 0, limit: 200).
- Per-category renderer components pattern match on message.domain then message.name.
- EntryFormatter removed from live hot path. Renderers handle formatting.

## MessageRouter
- Single `send/1` API. Plain module (Iron Law). Replaces 10 paths.

## AgentWatchdog
- Merged from 4 GenServers: heartbeat + agent_monitor + nudge_escalator + pane_monitor.
- One `:beat` timer at 5s. 3 pure helpers: EventState, NudgePolicy, PaneParser.

## Performance Patterns
- LiveView Streams for real-time feeds (no list assigns at scale).
- No Task.async per signal -- worse than struct allocation.
- Push filters into ETS. Single-pass Enum. Stream over Enum on hot paths.

## Consolidation Heuristics (functional, not OOP)
- Same data shape = same module. Single caller = private function.
- Call graph clustering: always co-occur = one module.
- Ash DSL replaces most helper modules (calculations, aggregates, preparations, generic actions).
- Module justifies existence by owning: process, framework callback, or multi-caller contract.

## Critical Constraints
- Module limit: 200L guide, SRP is the real rule.
- Dispatch params first, accumulators first, unused params last.
- Structs are contracts. Use @enforce_keys and @type t.
- credo --strict clean. Zero warnings.
- No decorative banners. No backward compat shims.
- All edits surgical. Frontend must keep working.

## Ecto→Ash Candidates (deferred, needs design session)
- mesh/decision_log.ex (6 nested Ecto schemas)
- gateway/webhook_delivery.ex + webhook_router.ex (raw Repo calls)
- gateway/cron_job.ex + cron_scheduler.ex (raw Repo calls)
- gateway/hitl_intervention_event.ex

## User Preferences
- "Always go for pragmatism"
- "Take ownership" = fix ALL issues including pre-existing
- "Always consult codex for architecture decisions"
- "All agents must be ash-elixir-expert"
- "Coordinate whenever possible -- delegate, don't code directly"
- "Split work evenly across agents"
- "No backward compat. Surgical edits. Frontend must work."
- "Ash Resources always need a domain. Never called directly."
- "Signals is our nervous system -- mass decoupling and chaining"
