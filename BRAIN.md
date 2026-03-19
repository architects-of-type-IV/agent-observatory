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

## Core Principles
- Domain is the ONLY public API. Resources NEVER called directly.
- Ash DSL replaces custom helpers (calculations, aggregates, preparations, generic actions).
- No raw Ecto.Schema/Changeset/Repo (exception: DecisionLog transport envelope).
- Module exists only if it owns: process, framework callback, or multi-caller contract.
- Same data shape = same module. Single caller = private function.
- Signals is the nervous system -- mass decoupling and chaining.

## AshAi Tool Scoping
- Ichor.Tools.Profiles: agent/0 and archon/0 tool lists
- Router: /mcp (agent tools), /mcp/archon (archon tools)
- Ash.can? policies for secondary filtering

## Signal-First Architecture
- Buffer stores {seq, %Message{}}. LiveView streams (at: 0, limit: 200).
- Per-category renderers. EntryFormatter removed from hot path.
- 13 Ash.Type.Enums for constraint enforcement.

## What's Next
- Physical file reorganization: move files to match 4-domain directory structure
- RunProcess lifecycle consolidation
- Component library

## User Preferences
- Always consult codex. All agents ash-elixir-expert. Coordinate and delegate.
- No backward compat. Surgical edits. Frontend must work. Split work evenly.
- Tests during refactor: delete, don't adapt. Resources always through domain.

## Namespace Consolidation (2026-03-19)
- Genesis + Mes + Dag all merged into Ichor.Projects
- Supervisors get semantic names: PlanSupervisor, LifecycleSupervisor, ExecutionSupervisor
- RunProcess instances: PlanRunner (genesis), BuildRunner (mes), RunProcess (dag)
- Dag.Projects -> Catalog; Dag.Analysis -> DagAnalysis; Dag.Prompts -> DagPrompts
- Genesis.Task -> RoadmapTask (collision avoidance with Ash.Type concepts)
- Multi-alias forms (alias Mod.{A,B}) not handled by perl s/// -- require manual grep+fix
- `has_many` relationship destination_attribute must be explicit when FK name != resource_snake_case + "_id"
