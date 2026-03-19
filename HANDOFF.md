# ICHOR IV - Handoff

## Current Status: Major Refactoring Session COMPLETE (2026-03-19)

### Session Summary

Coordinator-driven session with ash-elixir-expert agents and codex (GPT-5.4). Achieved: 10→4 Ash Domains, 3 Ecto→Ash conversions, signal livefeed refactor, AgentWatchdog merge, 22 modules inlined, 13 Ash.Type.Enums, Tool Profiles, doc/spec sweep.

### Domain Architecture (4 domains)

| Domain | Resources | Config |
|--------|-----------|--------|
| Ichor.Control | Fleet.Agent, Fleet.Team, Workshop.*, WebhookDelivery, CronJob (9) | ash_domains |
| Ichor.Projects | Genesis.* (10), Mes.Project, Dag.Run, Dag.Job (13) | ash_domains |
| Ichor.Observability | Events.*, Activity.*, Signals.Event, HITLInterventionEvent (7) | ash_domains |
| Ichor.Tools | AgentTools.* (12), Archon.Tools.* (9) (21) | ash_domains |

Signals bus (emit/subscribe/Message/Buffer/Catalog) = infrastructure, not a domain.

### What Was Done
1. Domain consolidation: 10 → 4 Ash Domains (Phases 0-4)
2. Ecto→Ash: WebhookDelivery, CronJob, HITLInterventionEvent converted
3. Signal livefeed: LiveView streams, per-category renderers, filter fix
4. AgentWatchdog: 4 GenServers → 1 + 3 pure helpers
5. Module inlining: ~22 files eliminated across 2 rounds
6. Ash.Type.Enum: 13 total extracted
7. Tool Profiles: Ichor.Tools.Profiles with agent/0 and archon/0
8. /mcp/archon endpoint wired
9. Tool name collisions resolved (4 mismatches fixed per codex review)
10. Quality: banners removed, @enforce_keys, @type t, validate_config_inclusion?
11. Doc/spec sweep: 5 agents dispatched (may still be running)

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- CLEAN
- Server needs restart to pick up all domain changes
- DecisionLog stays as Ecto embedded_schema (correct per codex)

### What's Next (Priority Order)
1. **PHYSICAL FILE REORGANIZATION** -- module namespaces still reflect old domains. Files need to move to match 4-domain structure. ~150 module renames + all reference updates.
2. RunProcess lifecycle consolidation (3 parallel implementations → shared)
3. Component library (variant-based primitives)
4. Server restart + MES team relaunch
5. Phase 5 remainder (deeper inlining, diminishing returns)

### Research Documents
- docs/plans/2026-03-19-domain-consolidation.md
- docs/plans/2026-03-19-component-library-research.md
- docs/plans/2026-03-19-quality-audit.md
- docs/plans/2026-03-19-ash-ai-tool-scoping.md

### Key Memory Files
- memory/project/domain_architecture.md -- agreed 4-domain structure
- memory/project/ecto_to_ash_candidates.md -- codex-designed conversion plan
- memory/feedback/coordinator_role.md -- delegate, don't code directly
- memory/feedback/always_consult_codex.md -- codex before every architectural move
- memory/feedback/ash_expert_agents.md -- all agents must be ash-elixir-expert
- memory/feedback/surgical_edits.md -- minimum changes, no backward compat
- memory/feedback/split_work_evenly.md -- distribute work across agents
- memory/feedback/tests_during_refactor.md -- delete tests for inlined modules
