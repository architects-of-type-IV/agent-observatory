# ICHOR IV - Handoff

## Current Status: Domain Consolidation COMPLETE + Ecto→Ash COMPLETE (2026-03-19)

### Session Summary

Coordinator-driven session with ash-elixir-expert agents and codex (GPT-5.4). Achieved: 10→4 Ash Domains, 3 Ecto→Ash conversions, signal livefeed refactor, AgentWatchdog merge, module consolidation, quality fixes.

### Domain Architecture (FINAL)

| Domain | Resources | Role |
|--------|-----------|------|
| Ichor.Control | Fleet.Agent, Fleet.Team, Workshop.*, WebhookDelivery, CronJob | Agents, configs, spawning, operational delivery |
| Ichor.Projects | Genesis.*, Mes.Project, Dag.Run, Dag.Job | Project lifecycle: planning → coherence → execution |
| Ichor.Observability | Events.*, Activity.*, Signals.Event, HITLInterventionEvent | Everything that happened |
| Ichor.Tools | AgentTools.* (12), Archon.Tools.* (9) | MCP surfaces, capability-based |

Signals bus (emit/subscribe/Message/Buffer/Catalog) stays as infrastructure -- not a domain.

### Ecto→Ash Conversions Done
- WebhookDelivery → Ash Resource in Control (8 Repo calls eliminated)
- CronJob → Ash Resource in Control (all Repo calls eliminated)
- HITLInterventionEvent → Ash Resource in Observability (append-only audit trail)
- DecisionLog → stays as Ecto embedded_schema (correct design per codex)

### Other Session Work
- Signal livefeed: LiveView streams, per-category renderers, filter fix, timestamp fix
- AgentWatchdog: 4 GenServers → 1 + 3 pure helpers
- Module consolidation: deleted archon.ex, mailer.ex, RuntimeHooks/Runtime, delegation chains
- Ash.Type.Enum: 7 extracted (5 domain + DeliveryStatus + HITLAction)
- Quality: banners removed, @enforce_keys, @type t, validate_config_inclusion? re-enabled

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- CLEAN (0 issues)
- Server needs restart to pick up domain changes

### What's Next
1. Phase 5: Module inlining (51 files identified for single-caller collapse)
2. AshAi tool profiles (Ichor.Tools.Profiles with agent/0 and archon/0)
3. /mcp/archon endpoint for Archon-specific tool access
4. Component library (variant-based primitives -- research at docs/plans/2026-03-19-component-library-research.md)
5. RunProcess lifecycle consolidation (3 parallel implementations)
6. Remaining Ash.Type.Enum extraction (6 MEDIUM/LOW candidates)

### Research Documents
- docs/plans/2026-03-19-domain-consolidation.md
- docs/plans/2026-03-19-component-library-research.md
- docs/plans/2026-03-19-quality-audit.md
- docs/plans/2026-03-19-ash-ai-tool-scoping.md
