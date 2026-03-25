# ICHOR IV Glossary

Canonical definitions. When two words could mean the same thing, this file says which one we use and what the other one means.

Related: [Database Schema](../diagrams/database-schema.md) | [Architecture Diagrams](../diagrams/architecture.md)

---

## Overloaded Terms (same word, different meaning by context)

| Word | In Factory | In Workshop | In Infrastructure | In general |
|------|-----------|------------|-------------------|-----------|
| **Project** | A planning brief being turned into requirements. Has artifacts, a roadmap, and a lifecycle status | Not used | Not used | A git repository. External projects have their own `tasks.jsonl` |
| **Team** | A runtime group of agents executing a run. Ephemeral -- exists only while the run is alive | A saved team design on the canvas. Persistent -- agents, spawn links, comm rules | The OTP grouping that lets us list members and disband | Never a human team |
| **Agent** | Not used directly | A live Claude instance viewed through the fleet. Also: an agent type (a reusable template for configuring agents) | The BEAM process that holds an agent's mailbox, backend, and state | A Claude Code instance running in tmux |
| **Task** | A unit of work in a pipeline. One line in `tasks.jsonl`. Has dependencies, an owner, a status | Not used | Not used | Never an Elixir `Task` or Oban job |
| **Pipeline** | A single build execution attempt. Groups tasks into a run | Not used | Not used | Never a Unix pipe or data pipeline |
| **Run** | An execution lifecycle with a kind (mes/pipeline/planning), a session, and a timeline | Not applicable -- workshop launches are fire-and-forget, no lifecycle monitor | Not used | Not "running" as in process state |
| **Session** | The tmux session that hosts a run's agent windows (e.g., `"mes-abc123"`) | Not used | The tmux session as an infrastructure concern | Not a web session or Phoenix session |
| **Status** | Varies per concept: pipeline (active/completed/failed/archived), task (pending/in_progress/completed/failed), project (proposed/in_progress/compiled/loaded/failed) | Not used for teams (they're ephemeral) | Agent (active/idle/ended), webhook (pending/delivered/failed/dead) | Each concept has its own status values. Never interchangeable |
| **Spec** | Not used | The compiled launch contract: a team design transformed into something infrastructure can execute | The runtime struct that TeamLaunch consumes: session name, agent list, prompt directory | A spec is always a compiled artifact, never a design |
| **Spawn** | `spawn("pipeline")` -- spawn the team named "pipeline" for this project. What the team does is defined by its Workshop config and prompts | `spawn("my-team")` -- spawn any designed team by name. Workshop owns the design; spawn just compiles and launches | Execute the compiled spec: write scripts, create tmux windows, register agents | `spawn/1` is generic: team name -> compile design -> launch. Page-independent. What the team does is determined by its prompts, not by the spawn call |

---

## Roles

| Term | Definition | Not to be confused with |
|------|-----------|----------------------|
| **Architect** | The human user who designs systems and steers agents | An agent role |
| **Archon** | The AI agent that manages the entire ICHOR app. Elevated role, not a peer agent | A domain name (Ichor.Archon is also the Ash Domain for Archon's tool surface) |
| **Operator** | The messaging relay identity used when the human sends messages through the dashboard | The human themselves (the human is the Architect, the Operator is a relay persona) |
| **Agent** | A Claude Code instance running in a tmux window, registered in the fleet | A GenServer (AgentProcess is the BEAM-side representation, the Agent is the Claude process) |
| **Coordinator** | The lead agent in a team who delegates work to other agents | Not a GenServer or supervisor |
| **Lead** | Second-in-command agent in a team. Receives work from coordinator, may delegate to workers | |
| **Worker** | An agent that implements tasks assigned by the coordinator or lead | An Oban worker (different concept entirely) |

## Domains

| Term | Definition | Page | Not to be confused with |
|------|-----------|------|----------------------|
| **Workshop** | Domain for designing and building agents and teams | `/workshop` | Factory (Workshop designs, Factory executes) |
| **Factory** | Domain for turning project-briefs into project requirements via MES pipeline | `/mes` | Workshop (Factory plans and builds projects, not teams) |
| **Archon** | Domain exposing Archon's management tool surface (Manager, Memory) | system-wide | The Archon agent itself (the domain is the tool surface, the agent is the identity) |
| **Signals** | Ash Domain for the reactive pub/sub backbone. Owns the GenStage pipeline, SignalProcess accumulators, Bus, and Checkpoint resources (ADR-026) | `/signals` | A message bus (Bus is for agent-to-agent messages; Signals is for system events) |
| **Events** | Ash Domain for durable event storage. Owns the append-only StoredEvent log | system-wide | The signal pipeline (Events stores raw data; Signals processes and routes it) |
| **Infrastructure** | I/O boundary only: external adapters wrapped as Ash Resources with `:none` data layer (tmux, webhook, Memories API). No business logic, no supervisors | none | Fleet (fleet owns OTP processes; Infrastructure owns external I/O) |
| **Fleet** | OTP process layer: AgentProcess GenServers, TeamSupervisor, FleetSupervisor. Manages live agent lifecycle in BEAM | none | Infrastructure (fleet is OTP process management; infrastructure is external I/O) |
| **Orchestration** | Use-case orchestrators: agent and team launch/cleanup. Composes fleet and infrastructure into complete workflows | none | Fleet (orchestration calls fleet + infrastructure; fleet owns the processes) |

## Concepts

| Term | Definition | Not to be confused with |
|------|-----------|----------------------|
| **Signal** | A domain event accumulated and flushed by the GenStage pipeline (ADR-026). A `%Signal{}` struct carries the events that triggered a flush for a given `{signal_module, key}` pair. Distinct from a raw `%Event{}` | A message (signals are system-level events; messages are directed agent-to-agent communications) |
| **Message** | A directed communication from one agent/operator to another, delivered via Bus | A signal (messages have a sender, recipient, and content; signals are fire-and-forget broadcasts) |
| **Bus** | `Ichor.Signals.Bus` -- the message delivery authority. Routes agent-to-agent and operator-to-agent messages | The Signals domain (Bus delivers directed messages; Signals routes system events. Different systems) |
| **Event** | A hook event from a Claude agent, received via HTTP POST to `/api/events`. Also: any domain event emitted by the `FromAsh` Ash notifier | A signal (events are raw input data; signals are processed domain events) |
| **StoredEvent** | Ash resource: append-only durable log of all events in PostgreSQL. Used for replay and projection rebuilds | A signal (StoredEvent is persistence; signals are ephemeral processing artifacts) |
| **Ingress** | GenStage producer at the head of the signal pipeline. Receives events and buffers them for downstream consumers | A web endpoint (Ingress is a GenStage process, not HTTP) |
| **Router** | GenStage consumer that dispatches events to per-topic `SignalProcess` instances. One Router receives from one Ingress | A Phoenix router (the signal Router routes events; the Phoenix router routes HTTP/LiveView) |
| **SignalProcess** | Stateful accumulator GenServer per `{signal_module, key}` pair. Collects events and flushes a `%Signal{}` when the module's condition is met | AgentProcess (SignalProcess accumulates events; AgentProcess manages a live agent's BEAM state) |
| **ActionHandler** | Dispatches flushed signals to concrete system actions (Oban job insertion, Bus delivery, log emission) | A Phoenix controller action |
| **Checkpoint** | Ash resource that tracks the last processed event ID per signal module. Enables crash-safe pipeline resume without reprocessing | A git checkpoint or stage gate |
| **EventStream** | ETS-backed event buffer + liveness tracking. Stores hook events, emits normalised events into the pipeline (canonical event owner) | A live stream (it's a store you query, despite the name) |
| **Team** | A group of agents with defined roles, spawn links, and comm rules | A tmux session (a team runs IN a tmux session, but the team is the logical group) |
| **Session** | A tmux session that hosts one or more agent windows | An agent (a session contains agents; `session_id` identifies the tmux session, not the agent) |
| **Session ID** | A string identifying an agent's tmux window within a session. Format: `"{session}-{agent-name}"` | A tmux session name (session ID is per-agent-window, session name is per-team) |
| **Run** | A single execution of a planning mode or pipeline. Has a `run_id`, a `kind`, and a lifecycle | A project (a project can have many runs) |
| **Pipeline** | An Ash resource tracking a pipeline execution run. One per build attempt | A Unix pipeline or data pipeline |
| **PipelineTask** | An Ash resource representing one task in a pipeline. Has status, owner, dependencies | A background job (PipelineTasks are tracked units of work for agents, not Oban jobs) |
| **PipelineQuery** | Pure module that reads `tasks.jsonl` and computes board state on demand. Replaced PipelineMonitor GenServer | A GenServer (PipelineQuery has no process; LiveView calls it directly) |

## Technical Concepts

| Term | Definition | Not to be confused with |
|------|-----------|----------------------|
| **TeamSpec** | A compiled runtime launch contract. Contains agent specs, prompts, metadata, session config. Accepts `prompt_module` opt for strategy injection (AD-6) | A team definition (the Team Ash resource is the design; TeamSpec is the compiled-for-launch artifact) |
| **AgentSpec** | A single agent's launch specification within a TeamSpec | An agent type (AgentType is a template; AgentSpec is a concrete launch instruction) |
| **CanvasState** | The Workshop canvas state: agent positions, spawn links, comm rules. Used to compile TeamSpecs | The UI state (CanvasState is the data model, not the React/LiveView component state) |
| **Preset** | A named team template (e.g., "mes", "pipeline", "review"). Pre-configured team designs | A default value (presets are full team configurations, not single-field defaults) |
| **Spawn Link** | A directed dependency edge between agents in a team. Agent B spawns after Agent A | An Erlang link (spawn links are team topology, not process links) |
| **Comm Rule** | A communication policy between agents. Defines who can message whom and how | An Erlang behaviour or protocol |

## Run Kinds

| Term | Definition | Triggered by |
|------|-----------|-------------|
| **MES run** | Autonomous planning cycle. Scheduler ticks every 60s. Produces briefs and requirements | MesScheduler automatic tick |
| **Planning run** | Mode A/B/C execution. Architect-initiated. Produces ADRs, FRDs, or roadmaps | User clicks "Mode A/B/C" on MES page |
| **Pipeline run** | Multi-agent build execution. Agents implement tasks from a roadmap in parallel | User clicks "Build" on MES page |
| **Workshop launch** | Ad-hoc team launch from the Workshop canvas. No lifecycle monitor (Runner) | User clicks "Launch Team" on Workshop page |

## Fleet and Orchestration

| Term | Definition | Not to be confused with |
|------|-----------|----------------------|
| **FleetSupervisor** | DynamicSupervisor (`Ichor.Fleet.Supervisor`) that owns all AgentProcess instances | A team supervisor |
| **TeamSupervisor** | Per-team DynamicSupervisor (`Ichor.Fleet.TeamSupervisor`). Organizes agents for group operations (list members, disband) | FleetSupervisor (TeamSupervisor is logical grouping; FleetSupervisor is OTP supervision) |
| **AgentProcess** | GenServer representing a live agent in the BEAM. Holds mailbox, backend, status | The Claude process (AgentProcess is the BEAM side; the Claude agent runs in tmux) |
| **TeamLaunch** | Orchestration module (`Ichor.Orchestration.TeamLaunch`) that executes a TeamSpec: writes scripts, creates tmux sessions, registers agents | Workshop.Spawn (TeamLaunch is the execution; Spawn is the domain orchestrator that calls it) |
| **Registry** | `Ichor.Registry` -- Elixir Registry for agent process lookup by ID | A service registry or DNS |
| **Board** | File-backed task board (`tasks.jsonl`). Used by PipelineQuery for external project interop | Dashboard (the Board is the data; the Dashboard is the UI) |
| **FleetLifecycle** | Projector (`Ichor.Projector.FleetLifecycle`) that reacts to fleet signals by spawning/terminating AgentProcess and TeamSupervisor instances | AgentWatchdog (FleetLifecycle handles fleet mutations; AgentWatchdog monitors health) |
| **CleanupDispatcher** | Projector (`Ichor.Projector.CleanupDispatcher`) that routes cleanup signals to Oban workers (archive, reset, disband, kill) | TeamWatchdog (the dispatcher inserts jobs; TeamWatchdog emits the signals) |

## Implemented (formerly planned)

| Term | Definition |
|------|-----------|
| **RunRef** | `Ichor.Factory.RunRef` -- plain struct with `parse/1`, `session_name/1`, `registry_key/1`, `supervisor/1`. Replaces 5x3 clause trees and string parsing across 7 files (AD-7) |
| **AgentId** | `Ichor.Workshop.AgentId` -- plain struct with `parse/1`, `format/1`, `build/3`. Parses session ID strings like `"mes-abc123-coordinator"` into `%{kind, run_id, role}` (AD-7) |
| **Operator.Inbox** | `Ichor.Operator.Inbox` -- owns `~/.claude/inbox/` write path with schema. Single write authority (A3) |

## Planned

| Term | Definition |
|------|-----------|
| **Discovery** | `Ichor.Discovery` -- will expose all Ash actions grouped by Domain for dynamic workflow composition through the UI |
| **Workflow** | A user-composed pipeline of Ash actions, built in the UI by piping action outputs to action inputs |

## Oban Workers

| Worker | Queue | Schedule | Purpose |
|--------|-------|----------|---------|
| **MesTick** | scheduled | cron 1m | MES planning run scheduler tick |
| **ScheduledJob** | scheduled | on-demand | Fires a scheduled job signal for agents |
| **WebhookDeliveryWorker** | webhooks | on-demand | HTTP POST with HMAC, exponential backoff, max 5 attempts |
| **ArchiveRunWorker** | maintenance | on-demand | Archives completed pipeline run (AD-8 cleanup) |
| **ResetRunTasksWorker** | maintenance | on-demand | Resets in_progress tasks for a failed run (AD-8 cleanup) |
| **DisbandTeamWorker** | maintenance | on-demand | Disbands team supervisor (AD-8 cleanup) |
| **KillSessionWorker** | maintenance | on-demand | Kills tmux session (AD-8 cleanup) |
| **HealthCheckWorker** | maintenance | cron 1m | Runs health check script, emits :pipeline_health_report |
| **ProjectDiscoveryWorker** | maintenance | cron 1m | Scans for tasks.jsonl files, emits :pipeline_status |
| **OrphanSweepWorker** | maintenance | cron 5m | Cleans up orphaned teams with no live agents |
| **PipelineReconcilerWorker** | maintenance | cron 5m | AD-8 safety net: archives pipelines stuck in :active with no Runner |
| **PruneStoredEventsWorker** | maintenance | cron daily 3am | Prunes StoredEvent records older than 7 days; keeps append-only log bounded |
