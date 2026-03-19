# ICHOR IV - Handoff

## Current Status: Domain Consolidation (2026-03-19) -- Phase 3 Complete, Phase 4 In Progress

### Session Summary

Coordinator-driven session with ash-elixir-expert agents and codex (GPT-5.4) as architecture partner. Massive domain consolidation: 10 Ash Domains → 5 (target: 4). Plus signal livefeed refactor, AgentWatchdog merge, module consolidation, and quality fixes.

### Domain Consolidation Progress

| Phase | What | Status |
|-------|------|--------|
| Phase 0 | Bootstrap empty Control, Projects, Observability | Done |
| Phase 1 | Events + Activity + Signals.Domain → Observability (6 resources) | Done |
| Phase 2 | Fleet + Workshop → Control (7 resources) | Done |
| Phase 3 | Genesis + MES + DAG → Projects (13 resources) | Done |
| Phase 4 | AgentTools + Archon.Tools → Tools | In Progress (tool name collision audit done, codex naming consultation pending) |

### Current ash_domains (5):
- Ichor.AgentTools
- Ichor.Archon.Tools
- Ichor.Control (7 resources: Fleet.Agent, Fleet.Team, Workshop.*)
- Ichor.Observability (6 resources: Events.*, Activity.*, Signals.Event)
- Ichor.Projects (13 resources: Genesis.*, Mes.Project, Dag.Run, Dag.Job)

### Phase 4 Tool Name Collisions (must resolve before merge)
4 collisions found between AgentTools and Archon.Tools:
- :list_agents -- different semantics (memory registry vs live fleet)
- :spawn_agent -- same backend, different strictness
- :stop_agent -- same backend, different return shapes
- :send_message -- different caller semantics (agent-to-agent vs operator-to-agent)

Codex naming consultation dispatched. Approach: merge domains but not meanings. Scoped MCP endpoints (/mcp/agent, /mcp/archon).

### Other Session Accomplishments

1. **Signal livefeed refactor** -- Buffer stores {seq, %Message{}}, LiveView streams (not list assigns), 10 per-category renderer components, filtering via stream reset
2. **AgentWatchdog merge** -- 4 GenServers → 1 + 3 pure helpers
3. **Module consolidation** -- deleted archon.ex, mailer.ex, RuntimeHooks, Runtime. Moved janitor, heartbeat. Collapsed 4-hop delegation chains.
4. **Ash.Type.Enum** -- 5 HIGH priority enums extracted
5. **Quality fixes** -- banners removed, @enforce_keys on 6 structs, @type t on 5 modules, validate_config_inclusion? re-enabled
6. **Domain centralization** -- Genesis (27 functions), Workshop (6), MES (3) all centralized earlier in session
7. **Codex review** -- PASS with one fix (stale template string)

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- CLEAN (0 issues)
- `validate_config_inclusion?` re-enabled on all 3 new domains
- Server needs restart to pick up domain changes

### What's Next
1. Complete Phase 4 (Tools merge -- resolve naming, create Ichor.Tools, split MCP router)
2. Phase 5: Module inlining (51 files identified)
3. Ecto→Ash migration (4 areas: DecisionLog, WebhookDelivery, CronJob, HITLInterventionEvent)
4. RunProcess lifecycle consolidation (3 parallel implementations → shared)
5. Component library (variant-based primitives -- research done, docs/plans/2026-03-19-component-library-research.md)

### Research Documents Created
- docs/plans/2026-03-19-domain-consolidation.md
- docs/plans/2026-03-19-component-library-research.md
- docs/plans/2026-03-19-quality-audit.md
