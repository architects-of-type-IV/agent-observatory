# Vertical Slices -- What Users Do

Diagrams: [architecture.md](../diagrams/architecture.md) | Audit: [architecture-audit.md](2026-03-21-architecture-audit.md)

## The Use Cases

### UC1: Design a Team (Workshop)
**As an** architect, **I want to** arrange agents on a canvas with roles, spawn links, and comm rules, **so that** I can reuse team configurations across projects.

**Slice**: Canvas UI -> Workshop.Team (Ash) -> TeamMember, AgentSlot, SpawnLink, CommRule (embedded)
**Owned entirely by**: Workshop domain. Clean.

### UC2: Launch a Team (Workshop)
**As an** architect, **I want to** click "Launch" on a saved team design, **so that** agents start running in tmux with the designed topology.

**Slice**: Canvas UI -> Workshop.Spawn -> TeamSpec compilation -> TeamLaunch -> tmux
**What happens**: Design (Workshop data) is compiled into a runtime spec (Infrastructure contract), then executed.
**The compilation step**: Workshop.TeamSpec.compile -- takes canvas state, produces Infrastructure.TeamSpec. This is Workshop's job because it owns the design.

### UC3: Start Planning (Factory)
**As an** architect, **I want to** kick off Mode A/B/C for a project, **so that** a team of agents produces ADRs/FRDs/roadmap from my brief.

**Slice**: MES UI -> Factory.Spawn(:planning) -> TeamSpec.build(:planning) -> TeamLaunch -> Runner(:planning) -> tmux
**What happens**: Factory provides the context (brief, mode, project). Workshop compiles the team. Infrastructure launches it. Runner monitors it.

### UC4: Build a Project (Factory)
**As an** architect, **I want to** click "Build" to launch a pipeline that implements the roadmap, **so that** agents execute tasks in parallel with dependency ordering.

**Slice**: MES UI -> Factory.Spawn(:pipeline) -> Loader (tasks) -> Validator (DAG) -> WorkerGroups -> TeamSpec.build(:pipeline) -> TeamLaunch -> Runner(:pipeline) -> tmux
**What happens**: Factory loads tasks, validates the DAG, groups into workers. Workshop compiles the team. Infrastructure launches. Runner monitors. PipelineMonitor tracks external file state.

### UC5: Monitor the Fleet (Dashboard)
**As an** operator, **I want to** see all agents across all projects with their status, health, and current activity, **so that** I can intervene when something goes wrong.

**Slice**: Hook events (HTTP) -> EventStream (ETS) -> Signals -> LiveView subscriptions -> Dashboard UI
**What happens**: Claude agents emit hook events. EventStream stores them and auto-registers agents. AgentWatchdog detects stale agents. Dashboard subscribes to signals and renders.

### UC6: Communicate with Agents (Dashboard)
**As an** operator, **I want to** send messages to agents, teams, or broadcast to all, **so that** I can steer agent behavior.

**Slice**: Dashboard UI -> Bus.send -> AgentProcess.send_message / Tmux.deliver
**What happens**: Bus resolves the target (agent, team, role, fleet), delivers the message, logs it, broadcasts the delivery signal.

### UC7: Manage Pipeline Tasks (Dashboard)
**As an** operator, **I want to** see task status, heal stuck tasks, reassign failed ones, and track pipeline health, **so that** pipelines complete successfully.

**Slice**: Dashboard UI -> PipelineMonitor -> tasks.jsonl (external files) + PipelineTask (Ash)
**Why two sources**: We monitor agents across ALL git projects. External projects use tasks.jsonl as their task interface. Our Ash PipelineTask is authoritative for runs we created; the file is how we interop.

### UC8: Archon Manages the System
**As the** Archon agent, **I want to** observe the system, manage agents, query memory, and clean up after failed runs, **so that** the system stays healthy autonomously.

**Slice**: Archon MCP tools -> Ash actions -> domain resources
**What happens**: Archon calls Ash actions through MCP. TeamWatchdog (currently in Archon namespace) reacts to run lifecycle signals.

---

## The Spawn Insight

`spawn/1` is generic: team name -> compile Workshop design -> launch in tmux. Page-independent. What the team does is determined entirely by its prompts and agent configuration in Workshop.

The current `:mes`, `:pipeline`, `:planning` are not architectural spawn modes -- they are **team configurations** that happen to be hardcoded. In the target state:

- `spawn("mes")` looks up the "mes" team in Workshop, compiles, launches
- `spawn("pipeline")` looks up the "pipeline" team, compiles, launches
- `spawn("ping-pong")` looks up "ping-pong", compiles, launches
- Any page can have a spawn button with a team dropdown

**Constraints live in signal subscribers, not in the spawner:**
- `spawn/1` emits `:team_spawn_requested`
- A subscriber pattern-matches on `team: "mes"` and checks if one is already running
- A subscriber pattern-matches on `team: "pipeline"` and checks DAG validity
- Teams with no matching subscriber clause just spawn freely
- No new concept needed -- this is just `handle_info` with pattern matching

**Implications for current code:**
- `TeamSpec.build(:mes | :pipeline | :planning)` dissolves into `TeamSpec.compile(workshop_state, opts)`
- `TeamPrompts`, `PipelinePrompts`, `PlanningPrompts` become Workshop-configured prompt templates per agent slot
- `Factory.Spawn` and `Workshop.Spawn` converge into one `spawn/1`
- `Runner` modes become team-level metadata, not code branches
- The MesScheduler is the first example of a spawn policy subscriber

---

## Where Slices Cross Boundaries (problems)

### Problem 1: UC3 and UC4 inject prompts through Workshop
Planning and pipeline prompts live in Factory (PlanningPrompts) and Workshop (PipelinePrompts). But the compilation happens in Workshop.TeamSpec which imports both.

**Root cause**: TeamSpec.build(:mes|:pipeline|:planning) puts caller knowledge inside the compiler.
**Clean slice**: Each caller (Factory.Spawn for UC3/UC4, Workshop.Spawn for UC2) owns its prompts and passes them to TeamSpec.compile as a strategy. Workshop.TeamSpec has no Factory imports.

### Problem 2: UC5 fleet mutations happen inside event ingestion
EventStream.ingest_event auto-creates AgentProcess entries. The event store is doing fleet management.

**Root cause**: Self-healing design -- any event auto-registers its agent. Pragmatic, but couples the event store to the fleet.
**Clean slice**: EventStream emits `:session_discovered` signal. A fleet subscriber (in Infrastructure) reacts by spawning AgentProcess. EventStream stays a store + broadcaster.

### Problem 3: UC7 has two data paths
PipelineMonitor reads from disk (tasks.jsonl). Dashboard also reads from Ash (PipelineTask). Both show "task status" but from different sources.

**Root cause**: External interop requirement. tasks.jsonl exists for compatibility with other projects' tooling.
**Clean slice**: Accept the two sources. PipelineMonitor is the external-file adapter. PipelineTask is our internal truth. They sync through Runner.Exporter (write-through). Make this explicit: PipelineMonitor.tasks() = "what the file says". PipelineTask.by_run() = "what our system says".

### Problem 4: UC8 cleanup reaches across all domains
TeamWatchdog calls Factory.Pipeline, Factory.PipelineTask, Factory.Spawn, Infrastructure.FleetSupervisor directly.

**Root cause**: Run cleanup is inherently cross-cutting. A run ends -> archive pipeline (Factory), reset tasks (Factory), disband team (Infrastructure), kill tmux (Infrastructure), notify operator.
**Clean slice**: TeamWatchdog emits `:run_cleanup_needed` with the run context. Each domain has a subscriber that handles its own cleanup. Factory subscribes and archives/resets. Infrastructure subscribes and disbands/kills. Operator.Inbox subscribes and notifies.

### Problem 5: UC5 watchdog is in Signals namespace
AgentWatchdog monitors fleet health. It's a fleet concern that happens to subscribe to signals.

**Root cause**: "Lives where its input comes from" rather than "lives where its purpose belongs."
**Clean slice**: Move to where its purpose is. It watches the fleet, so it belongs near the fleet (Workshop or a shared monitoring namespace). It subscribes to Signals as an implementation detail, not a domain affiliation.

---

## What This Reveals About Architecture

The system has **five vertical slices** (UC1-UC4 + UC5-UC8), but the code is organized by **horizontal layers** (Workshop resources, Factory resources, Signals infrastructure, Infrastructure adapters).

The friction points are always at slice boundaries:
- UC3/UC4 cross Workshop<->Factory at TeamSpec (prompt injection)
- UC5 crosses Signals<->Infrastructure at EventStream (fleet mutations)
- UC7 crosses Factory<->filesystem at PipelineMonitor (external files)
- UC8 crosses everything at TeamWatchdog (cleanup orchestration)

The Signals bus is the right decoupling mechanism for all four. The pattern is always:
1. The module that knows something happened emits a signal
2. The module that needs to react subscribes
3. Heavy/retryable reactions become Oban jobs

The remaining question for each problem:
- **Problem 1**: How do we restructure TeamSpec.build without breaking the three spawn paths?
- **Problem 2**: Is the self-healing agent registration worth the coupling? (Probably yes for now.)
- **Problem 3**: Is PipelineMonitor's GenServer justified or should it be a pure module + Oban cron?
- **Problem 4**: Which cleanup actions need Oban retry semantics vs. fire-and-forget?
- **Problem 5**: Is renaming/moving AgentWatchdog worth the churn?
