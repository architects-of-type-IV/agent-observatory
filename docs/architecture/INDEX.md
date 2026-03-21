# ICHOR IV Architecture Index
Related: [Glossary](../plans/GLOSSARY.md) | [Diagrams](../diagrams/architecture.md) | [Database Schema](../diagrams/database-schema.md)

---

## Documents in This Directory

| File | Description |
|------|-------------|
| [decisions.md](decisions.md) | Eight architectural decisions (AD-1 through AD-8) with rationale and consequences |
| [target-file-structure.md](target-file-structure.md) | Complete target `lib/ichor` tree grouped by domain boundary; current-to-target mapping |
| [supervision-tree.md](supervision-tree.md) | Mermaid supervision diagram, per-supervisor strategies, GenServer keep/eliminate table |
| [memory-strategy.md](memory-strategy.md) | ETS inventory, per-store specs, Enum vs Stream decision rules, memory risks |
| [workshop-domain.md](workshop-domain.md) | Workshop CRUD plan: agent types, teams, canvas, prompt management, spawn convergence |
| [factory-domain.md](factory-domain.md) | Factory domain: project lifecycle, pipeline tracking, runner, Oban worker replacements |
| [signals-domain.md](signals-domain.md) | Signals domain: EventStore, Bus, Buffer, Catalog, subscribers, reliability model |
| [infrastructure.md](infrastructure.md) | Infrastructure host layer: supervisors, registry, tmux, TeamLaunch, CommPolicy |

---

## Supporting Documents (plans/)

| File | Description |
|------|-------------|
| [plans/2026-03-21-architecture-blueprint.md](../plans/2026-03-21-architecture-blueprint.md) | Source blueprint with all eight ADs, ownership rules, gap analysis, 25-task wave plan |
| [plans/2026-03-21-architecture-audit.md](../plans/2026-03-21-architecture-audit.md) | Detailed audit findings by category (domain boundaries, duplication, process, missing abstractions) |
| [plans/2026-03-21-vertical-slices.md](../plans/2026-03-21-vertical-slices.md) | Nine use cases mapped to code slices; cross-boundary problem descriptions |
| [plans/2026-03-21-actionable-findings.md](../plans/2026-03-21-actionable-findings.md) | Prioritized actionable findings with file locations and effort estimates |
| [plans/GLOSSARY.md](../plans/GLOSSARY.md) | Canonical term definitions; overloaded terms disambiguated by domain |
| [reviews/2026-03-21-codex-sparring.md](../reviews/2026-03-21-codex-sparring.md) | Codex sparring session transcript; source of AD-8 reliability boundary decision |

---

## Diagrams

| File | Description |
|------|-------------|
| [diagrams/architecture.md](../diagrams/architecture.md) | Mermaid diagrams for all nine use cases, domain boundaries, signal flow, spawn flow |
| [diagrams/database-schema.md](../diagrams/database-schema.md) | ERD for all AshSqlite tables and embedded resources |

---

## Recommended Reading Order

1. [decisions.md](decisions.md) -- understand the eight load-bearing design choices before reading code
2. [plans/GLOSSARY.md](../plans/GLOSSARY.md) -- clarify overloaded terms (Team, Agent, Run, Pipeline, Spawn)
3. [diagrams/architecture.md](../diagrams/architecture.md) -- visual domain map and use-case flows
4. [plans/2026-03-21-vertical-slices.md](../plans/2026-03-21-vertical-slices.md) -- nine user-facing slices show where boundaries are clean vs. broken
5. [workshop-domain.md](workshop-domain.md) -- Workshop is the most complex domain; read before factory
6. [factory-domain.md](factory-domain.md) -- Factory depends on Workshop for team compilation
7. [signals-domain.md](signals-domain.md) -- Signals is the backbone; AD-2 and AD-8 govern it
8. [infrastructure.md](infrastructure.md) -- Host layer; called by Workshop and Factory, not a business domain
9. [supervision-tree.md](supervision-tree.md) + [memory-strategy.md](memory-strategy.md) -- runtime and data concerns
10. [target-file-structure.md](target-file-structure.md) -- reference during implementation; shows current-to-target mapping

---

## Status

- Codex sparring: complete (8.5/10 rating, 2026-03-21)
- Blueprint: approved
- Implementation: Wave 1 ready to dispatch (7 parallel tasks)
