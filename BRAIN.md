# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator.
- **Operator**: current thin messaging relay

## MES Factory Model (Factorio, 2026-03-16)
- **Core metaphor**: processes building processes
- **Signal bus** = COMMUNICATION bus (not conveyor belt). Broadcast medium.
- **Subsystem** = assembler (single pipe fitting, one GenServer, <200 lines)
- **Facility** = city block (self-contained composition of subsystems with standardized signal I/O)
- **Evolution path**: spaghetti -> main bus -> city blocks (facilities)
- **Facility teams deferred** -- need 3-5 loaded subsystems + signal catalog + dependency tracking first

## MES Prompt Design (2026-03-16)
- ResearchContext: dynamic gaps, subsystems, dead zones queried at spawn time
- Boundary map: what system HAS vs what it DOES NOT HAVE (gaps = opportunities)
- Pain points single-sourced in ResearchContext, not duplicated across prompts
- Results: WebhookEgress, Webhook Relay, SignalScheduler (all gap-filling utilities)

## Critical Constraints
- **No external SaaS** -- ADR-001. No Slack, Telegram, PagerDuty. Self-hosted only.
- **External apps DOWN** -- Memories (port 4000) and Genesis app broken (hardware)
- **Module limit**: 200 lines, single responsibility
- **Style**: pattern matching, no if/else/cond, @doc/@spec on public functions
- **Domain entrypoints**: Ash code_interface on resource is canonical

## Registry Architecture (2026-03-13)
- Single Ichor.Registry with compound keys: {:agent, id}, {:team, name}, {:run, id}
- Gateway.AgentRegistry ETS DELETED (Task 6)

## Ash/SQLite Patterns
- Manual migrations work when ash.codegen has snapshot issues
- Single Ichor.Repo (SQLite3) for all domains
- Domains: Fleet, Activity, Workshop, Archon, AgentTools, Events, Costs, Mes, Genesis

## Dashboard
- SessionEviction: purges stale sessions from @events (10min TTL, agent-agnostic)
- :agent_stopped handler triggers recompute for sidebar refresh
- DashboardState.recompute calls eviction before session derivation

## User Preferences (ENFORCED)
- "We dont filter. We fix implementation"
- "BEAM is god"
- "Always go for pragmatism"
- "Never think of solutions yourself. LLMs can judge and discuss."
- "Architect solutions with agents before coding"
- Minimal JS. No emoji. Execute directly.
