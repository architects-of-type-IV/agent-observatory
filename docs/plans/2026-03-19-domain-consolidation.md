# Domain Consolidation Plan

## Vision

10 Ash Domains → 4 Domains. Signals bus stays as infrastructure (nervous system).

- A fleet is nothing more than all agents
- A team is nothing more than agents with the same group name
- A blueprint is nothing more than a group of agents with instructions
- Genesis is nothing more than planning
- DAG is a graph of planned tasks that resolves into execution waves
- A swarm is a group of coordinated agents

## Target Architecture

### Ichor.Control (absorbs Fleet + Workshop)
Agent, AgentConfig, AgentType, SpawnLink, CommRule

### Ichor.Projects (absorbs Genesis + MES + DAG)
Project, Node, Adr, Feature, UseCase, Checkpoint, Conversation,
Phase, Section, Task, Subtask, Run, Job

### Ichor.Observability (absorbs Events + Activity + Signals.Domain)
Event, Session, Signal, Message, TaskActivity, Error

### Ichor.Tools (absorbs AgentTools + Archon.Tools)
Capability-based resources with policy profiles

### Signals Bus (infrastructure, not a domain)
emit/subscribe/Message/Buffer/Catalog -- the nervous system

## Migration Phases

### Phase 0: Bootstrap
- Create empty Ichor.Control, Ichor.Projects, Ichor.Observability domain modules
- Add to ash_domains in config
- Old domains remain live
- Verify coexistence compiles

### Phase 1: Observability (11 callers)
Resources: Events.Event, Events.Session, Activity.Message, Activity.Task, Activity.Error, Signals.Domain.Event
- Update domain: on each resource
- Update resources do block on Ichor.Observability
- Remove Ichor.Events, Ichor.Activity, Ichor.Signals.Domain from ash_domains
- Delete old domain files
- Update all callers
- Build + credo clean

### Phase 2: Control (44 callers)
Resources: Fleet.Agent, Fleet.Team, Workshop.TeamBlueprint, Workshop.AgentBlueprint, Workshop.AgentType, Workshop.SpawnLink, Workshop.CommRule
- Same pattern as Phase 1
- LiveView workshop handlers and spawner modules get updated in same commit

### Phase 3: Projects (37 callers)
Resources: Genesis.{Node, Adr, Feature, UseCase, Checkpoint, Conversation, Phase, Section, Task, Subtask}, Mes.Project, Dag.{Run, Job}
- Genesis.Node -> Mes.Project belongs_to must resolve in same commit
- Highest risk phase -- most cross-domain references

### Phase 4: Tools (4 callers)
Resources: AgentTools (12) + Archon.Tools (9) → Ichor.Tools
- AshAi extension must transfer to new domain
- Capability-based, not actor-based

### Phase 5: Module Inlining (51 files)
- Only after all domains stable
- Single-caller modules → inline as defp
- False modules → delete

## Rules
- No backward compatibility wrappers
- Rip-and-replace every reference per phase
- Frontend (LiveView) must work at every commit
- All edits surgical -- minimum changes needed
- Separate domain consolidation from semantic simplification
- Move resource ownership first, keep module names
- Dissolve concepts (Team, Workshop) only after domains stable
