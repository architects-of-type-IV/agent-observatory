# ICHOR IV Module Inventory

Classification legend used in this file:

- `GenServer`
- `Supervisor`
- `Ash Resource`
- `Ash Domain`
- `Plain Module`
- `Ash Preparation`
- `LiveView`
- `Controller`
- `Component`

The `lib/ichor` tree is almost entirely runtime/domain code, so most entries classify as `Plain Module`, `GenServer`, `Supervisor`, `Ash Resource`, `Ash Domain`, or `Ash Preparation`. Web modules such as controllers and LiveViews live in `lib/ichor_web`; those are noted at the end because they are part of the runtime request path.

## `/lib/ichor`

Core runtime root. This layer wires application boot, shared services, domains, message/signal infrastructure, observability, and subsystem supervisors.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.AgentWatchdog` | GenServer | Heartbeats, stale-agent nudges, crash detection, pane scanning. |
| `Ichor.Application` | Plain Module | Boots tmux, initializes counters/logs, starts the full supervision tree. |
| `Ichor.Architecture.BoundaryAudit` | Plain Module | Scans source files for boundary violations and coupling drift. |
| `Ichor.Control` | Ash Domain | Fleet control-plane domain for agents, teams, blueprints, and launch actions. |
| `Ichor.EventBuffer` | GenServer | Stores recent events in memory for dashboard and observability projections. |
| `Ichor.MemoriesBridge` | GenServer | Subscribes to signals and ingests observations into Memories. |
| `Ichor.MemoryStore` | GenServer | Owns in-memory/disk-backed agent memory state. |
| `Ichor.MessageRouter` | Plain Module | Canonical interface for delivering inter-agent/operator messages. |
| `Ichor.Notes` | Plain Module | ETS-backed note storage for operator annotations. |
| `Ichor.Observability` | Ash Domain | Domain for events, sessions, tasks, messages, and errors. |
| `Ichor.ObservationSupervisor` | Supervisor | Rest-for-one supervision for causal DAG, topology, and event bridge services. |
| `Ichor.Plugs.OperatorAuth` | Plain Module | Validates operator auth headers for HITL endpoints. |
| `Ichor.Projects` | Ash Domain | Domain for Genesis, MES, DAG, and subsystem execution records. |
| `Ichor.ProtocolTracker` | GenServer | Correlates message traces across HTTP, PubSub, mailbox, and filesystem transports. |
| `Ichor.QualityGate` | GenServer | Runs `done_when` gates and sends corrective nudges on failure. |
| `Ichor.Repo` | Plain Module | SQLite Ecto repo used by AshSqlite resources. |
| `Ichor.SystemSupervisor` | Supervisor | Supervises core, gateway, monitoring, and Archon services. |
| `Ichor.Tasks.Board` | Plain Module | CRUD-style team task board API with signal emission. |
| `Ichor.Tasks.JsonlStore` | Plain Module | Mutates `tasks.jsonl` rows in place for DAG/runtime repair. |
| `Ichor.Tasks.TeamStore` | Plain Module | File-backed task persistence per team. |
| `Ichor.Tools` | Ash Domain | Domain exposing MCP tools for agents and Archon. |

## `/lib/ichor/agent_watchdog`

Pure helper modules used by the consolidated watchdog process.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.AgentWatchdog.EventState` | Plain Module | Tracks session activity and team-name extraction from events. |
| `Ichor.AgentWatchdog.NudgePolicy` | Plain Module | Decides stale thresholds, escalation, and nudge eligibility. |
| `Ichor.AgentWatchdog.PaneParser` | Plain Module | Diffs tmux output and extracts DONE/BLOCKED patterns. |

## `/lib/ichor/architecture`

One-off architecture health checks and maintenance tooling.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Architecture.BoundaryAudit` | Plain Module | Reports direct Ash usage and legacy coupling patterns. |

## `/lib/ichor/archon`

Archon is the managerial/operator AI surface. It consumes signals, provides chat/tooling, and integrates with Memories.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Archon.Chat` | Plain Module | Top-level Archon conversation entrypoint for slash commands and LLM turns. |
| `Ichor.Archon.CommandManifest` | Plain Module | Registry of Archon commands, metadata, and quick actions. |
| `Ichor.Archon.MemoriesClient` | Plain Module | Makes HTTP requests to the external Memories API. |
| `Ichor.Archon.SignalManager` | GenServer | Maintains a compact managerial snapshot and attention queue from signals. |
| `Ichor.Archon.TeamWatchdog` | GenServer | Reacts to team/run signals to archive runs, reset jobs, and notify operator. |

### `/lib/ichor/archon/chat`

LangChain orchestration for Archon conversations.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Archon.Chat.ChainBuilder` | Plain Module | Builds the LLM chain and mounts Archon AshAi tools. |
| `Ichor.Archon.Chat.CommandRegistry` | Plain Module | Dispatches parsed slash commands to tool/resource actions. |
| `Ichor.Archon.Chat.ContextBuilder` | Plain Module | Retrieves graph-backed memory context for chat turns. |
| `Ichor.Archon.Chat.TurnRunner` | Plain Module | Executes one prepared Archon turn with history and memory context. |

### `/lib/ichor/archon/memories_client`

Value structs returned by `Ichor.Archon.MemoriesClient`.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Archon.MemoriesClient.ChunkedIngestResult` | Plain Module | Wraps chunked ingest responses. |
| `Ichor.Archon.MemoriesClient.IngestResult` | Plain Module | Wraps single ingest responses. |
| `Ichor.Archon.MemoriesClient.QueryResult` | Plain Module | Wraps query/retrieval responses. |
| `Ichor.Archon.MemoriesClient.SearchResult` | Plain Module | Wraps search result items. |

### `/lib/ichor/archon/signal_manager`

Pure signal-to-state projection for Archon manager state.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Archon.SignalManager.Reactions` | Plain Module | Maps incoming signals into dashboard-friendly manager state. |

### `/lib/ichor/archon/team_watchdog`

Pure reaction planning for the Archon team watchdog.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Archon.TeamWatchdog.Reactions` | Plain Module | Produces archive/reset/notify/disband actions from signals. |

## `/lib/ichor/control`

Fleet control plane. Owns agents, teams, Workshop blueprints, launch contracts, runtime projections, and live BEAM process hierarchy.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Control.Agent` | Ash Resource | Reads live agents and delegates write operations to runtime control modules. |
| `Ichor.Control.AgentBlueprint` | Ash Resource | Persists Workshop agent nodes and canvas metadata. |
| `Ichor.Control.AgentProcess` | GenServer | Live BEAM-native agent process with mailbox, delivery, and liveness state. |
| `Ichor.Control.AgentType` | Ash Resource | Persists reusable agent archetypes/defaults. |
| `Ichor.Control.BlueprintState` | Plain Module | Pure reducer for Workshop canvas edits. |
| `Ichor.Control.CommRule` | Ash Resource | Persists allow/deny/route communication rules between blueprints. |
| `Ichor.Control.FleetSupervisor` | Supervisor | Dynamic supervisor for team supervisors and standalone agents. |
| `Ichor.Control.HostRegistry` | GenServer | Tracks available cluster hosts via `:pg`. |
| `Ichor.Control.Lifecycle` | Plain Module | Public wrapper for team launch operations. |
| `Ichor.Control.Lookup` | Plain Module | Shared lookup and projection helpers for teams/agents. |
| `Ichor.Control.Persistence` | Plain Module | Saves and loads workshop data through the domain. |
| `Ichor.Control.Presets` | Plain Module | Defines canonical workshop presets and launch ordering. |
| `Ichor.Control.RuntimeQuery` | Plain Module | Queries live fleet/runtime state for the dashboard and tools. |
| `Ichor.Control.RuntimeView` | Plain Module | Shapes display-oriented runtime projections. |
| `Ichor.Control.SpawnLink` | Ash Resource | Persists directed spawn hierarchy edges. |
| `Ichor.Control.Team` | Ash Resource | Reads live teams and delegates team lifecycle actions. |
| `Ichor.Control.TeamBlueprint` | Ash Resource | Persists Workshop team blueprints. |
| `Ichor.Control.TeamSpecBuilder` | Plain Module | Converts workshop state into launchable team/agent specs. |
| `Ichor.Control.TeamSupervisor` | Supervisor | Dynamic supervisor for one team's `AgentProcess` children. |
| `Ichor.Control.TmuxHelpers` | Plain Module | Shared tmux-target parsing and shell helpers. |
| `Ichor.Control.Types.HealthStatus` | Plain Module | Ash enum type for health classification. |

### `/lib/ichor/control/agent_process`

Internal helper modules behind `Ichor.Control.AgentProcess`.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Control.AgentProcess.Delivery` | Plain Module | Normalizes messages and routes them to mailbox/tmux/SSH/webhook backends. |
| `Ichor.Control.AgentProcess.Lifecycle` | Plain Module | Schedules liveness checks and backend health probes. |
| `Ichor.Control.AgentProcess.Mailbox` | Plain Module | Buffers, broadcasts, and routes incoming messages. |
| `Ichor.Control.AgentProcess.Registry` | Plain Module | Builds registry metadata and tmux/session projections. |

### `/lib/ichor/control/analysis`

Pure analytics and projection helpers used by runtime views and the dashboard.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Control.Analysis.AgentHealth` | Plain Module | Computes failure rate, stuckness, and loop detection from events. |
| `Ichor.Control.Analysis.Queries` | Plain Module | Derives active sessions, teams, and fleet projections. |
| `Ichor.Control.Analysis.SessionEviction` | Plain Module | Evicts stale session events from projections. |

### `/lib/ichor/control/lifecycle`

Generic tmux-backed launch pipeline used by Workshop, MES, Genesis, and DAG orchestration.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Control.Lifecycle.AgentLaunch` | Plain Module | Spawns/stops individual tmux-backed agents and registers them. |
| `Ichor.Control.Lifecycle.AgentSpec` | Plain Module | Struct contract for one agent launch. |
| `Ichor.Control.Lifecycle.Cleanup` | Plain Module | Kills tmux sessions and clears launch artifacts. |
| `Ichor.Control.Lifecycle.Registration` | Plain Module | Registers tmux-backed launches into the live fleet. |
| `Ichor.Control.Lifecycle.TeamLaunch` | Plain Module | Creates multi-window tmux sessions and registers all agents. |
| `Ichor.Control.Lifecycle.TeamSpec` | Plain Module | Struct contract for one team launch. |
| `Ichor.Control.Lifecycle.TmuxLauncher` | Plain Module | Creates/kills tmux sessions and windows; checks availability. |
| `Ichor.Control.Lifecycle.TmuxScript` | Plain Module | Writes prompt and startup files for tmux-backed agents. |

### `/lib/ichor/control/types`

Ash custom types used by the control plane.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Control.Types.HealthStatus` | Plain Module | Enum values for `healthy`, `warning`, `critical`, `unknown`. |

### `/lib/ichor/control/views/preparations`

Ash preparations that project read models from runtime state rather than a single table.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Control.Views.Preparations.LoadAgents` | Ash Preparation | Loads agent records from registry/runtime state. |
| `Ichor.Control.Views.Preparations.LoadTeams` | Ash Preparation | Loads team records from runtime state and recent events. |

## `/lib/ichor/gateway`

Gateway/runtime transport layer. Owns message routing, delivery backends, heartbeats, entropy, HITL, cron, webhooks, and tmux discovery.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Gateway.Channel` | Plain Module | Behaviour contract for delivery adapters. |
| `Ichor.Gateway.CronJob` | Ash Resource | Persists scheduled jobs. |
| `Ichor.Gateway.CronScheduler` | GenServer | Schedules and runs recurring or one-time cron jobs. |
| `Ichor.Gateway.EntropyTracker` | GenServer | Detects low-entropy loops per session. |
| `Ichor.Gateway.Envelope` | Plain Module | Shapes normalized message envelopes. |
| `Ichor.Gateway.EventBridge` | GenServer | Converts buffered events into gateway message traffic. |
| `Ichor.Gateway.HeartbeatManager` | GenServer | Tracks heartbeats and timed-out agents. |
| `Ichor.Gateway.HITLInterventionEvent` | Ash Resource | Persists HITL interventions. |
| `Ichor.Gateway.HITLRelay` | GenServer | Manages per-session pause/unpause/rewrite/inject state. |
| `Ichor.Gateway.OutputCapture` | GenServer | Polls tmux panes and broadcasts output deltas. |
| `Ichor.Gateway.Router` | Plain Module | Central delivery bus that selects transport backends. |
| `Ichor.Gateway.SchemaInterceptor` | Plain Module | Validates inbound gateway payloads before routing. |
| `Ichor.Gateway.TmuxDiscovery` | GenServer | Discovers tmux sessions and reconciles fleet/session invariants. |
| `Ichor.Gateway.TopologyBuilder` | GenServer | Publishes topology snapshots for UI/observation consumers. |
| `Ichor.Gateway.WebhookDelivery` | Ash Resource | Persists webhook delivery attempts and dead-letter state. |
| `Ichor.Gateway.WebhookRouter` | GenServer | Executes durable webhook delivery with backoff/retry. |

### `/lib/ichor/gateway/agent_registry`

Shared agent-map helpers used by gateway/runtime projections.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Gateway.AgentRegistry.AgentEntry` | Plain Module | Builds normalized agent-entry maps. |

### `/lib/ichor/gateway/channels`

Concrete transport adapters behind the gateway router.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Gateway.Channels.MailboxAdapter` | Plain Module | Delivers directly to live BEAM mailboxes. |
| `Ichor.Gateway.Channels.SshTmux` | Plain Module | Delivers into remote tmux sessions over SSH. |
| `Ichor.Gateway.Channels.Tmux` | Plain Module | Delivers into local tmux sessions through buffers/paste operations. |
| `Ichor.Gateway.Channels.WebhookAdapter` | Plain Module | Enqueues durable webhook delivery. |

### `/lib/ichor/gateway/router`

Router helper modules.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Gateway.Router.EventIngest` | Plain Module | Ingests hook/event payloads into the gateway pipeline. |

## `/lib/ichor/memory_store`

Internal helpers behind the local memory system.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.MemoryStore.Persistence` | Plain Module | Saves and loads memory snapshots to disk. |
| `Ichor.MemoryStore.Storage` | Plain Module | All ETS operations: block CRUD, agent CRUD, recall, and archival. |

## `/lib/ichor/mesh`

Observation and causal-state modeling.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Mesh.CausalDAG` | GenServer | Maintains ETS-backed causal DAGs for active sessions. |
| `Ichor.Mesh.DecisionLog` | Plain Module | Ecto schema for universal decision-log envelopes. |

### `/lib/ichor/mesh/causal_dag`

Node structures used by the causal DAG.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Mesh.CausalDAG.Node` | Plain Module | Embedded/node schema used in DAG state. |

### `/lib/ichor/mesh/decision_log`

Embedded structures for decision-log metadata.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Mesh.DecisionLog.Action` | Plain Module | Embedded action payload details. |
| `Ichor.Mesh.DecisionLog.Cognition` | Plain Module | Embedded cognition payload details. |
| `Ichor.Mesh.DecisionLog.Control` | Plain Module | Embedded control metadata. |
| `Ichor.Mesh.DecisionLog.Identity` | Plain Module | Embedded actor/session identity metadata. |
| `Ichor.Mesh.DecisionLog.Meta` | Plain Module | Embedded envelope metadata. |
| `Ichor.Mesh.DecisionLog.StateDelta` | Plain Module | Embedded state-delta payloads. |

## `/lib/ichor/observability`

Read/query layer over event-derived operational data.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Observability.Error` | Ash Resource | Error projection derived from tool failure events. |
| `Ichor.Observability.Event` | Ash Resource | Canonical persisted hook event record. |
| `Ichor.Observability.EventAnalysis` | Plain Module | Timeline, analytics, and event-shaping helpers. |
| `Ichor.Observability.Janitor` | GenServer | Purges old SQLite observability rows. |
| `Ichor.Observability.Message` | Ash Resource | Message projection derived from send-message events. |
| `Ichor.Observability.Session` | Ash Resource | Session-oriented observability projection. |
| `Ichor.Observability.Task` | Ash Resource | Task projection derived from task update events. |

### `/lib/ichor/observability/preparations`

Preparations that read from the event buffer and shape query results.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Observability.Preparations.EventBufferReader` | Plain Module | Shared reader helper used by event-derived preparations. |
| `Ichor.Observability.Preparations.LoadErrors` | Ash Preparation | Builds error rows from failure events. |
| `Ichor.Observability.Preparations.LoadMessages` | Ash Preparation | Builds message rows from send-message events. |
| `Ichor.Observability.Preparations.LoadTasks` | Ash Preparation | Builds task rows from task hook events. |

## `/lib/ichor/plugs`

HTTP plugs consumed by the Phoenix router.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Plugs.OperatorAuth` | Plain Module | Authenticates operator requests for HITL actions. |

## `/lib/ichor/projects`

Project lifecycle subsystem spanning Genesis planning, MES manufacturing, DAG execution, subsystem scaffolding/loading, and runtime health.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Projects.Actions` | Plain Module | Mutates tasks and performs corrective DAG runtime actions. |
| `Ichor.Projects.Adr` | Ash Resource | Genesis ADR artifact. |
| `Ichor.Projects.BuildRunner` | GenServer | Owns one MES manufacturing run and its tmux team lifecycle. |
| `Ichor.Projects.Catalog` | Plain Module | Tracks discovered projects and active-project selection. |
| `Ichor.Projects.Checkpoint` | Ash Resource | Genesis gate checkpoint artifact. |
| `Ichor.Projects.CompletionHandler` | GenServer | Reacts to run completion by compiling/loading a subsystem. |
| `Ichor.Projects.Conversation` | Ash Resource | Genesis design conversation artifact. |
| `Ichor.Projects.DagAnalysis` | Plain Module | Parses tasks and derives DAG projections. |
| `Ichor.Projects.DagGenerator` | Plain Module | Converts Genesis roadmap hierarchy into DAG jobs. |
| `Ichor.Projects.DagPrompts` | Plain Module | Prompt templates for DAG execution teams. |
| `Ichor.Projects.DagTeamSpecBuilder` | Plain Module | Builds team specs for DAG execution runs. |
| `Ichor.Projects.Discovery` | Plain Module | Scans project directories and archives. |
| `Ichor.Projects.ExecutionSupervisor` | Supervisor | Supervises DAG run-process infrastructure. |
| `Ichor.Projects.Exporter` | Plain Module | Writes job state back to `tasks.jsonl`. |
| `Ichor.Projects.Feature` | Ash Resource | Genesis feature artifact. |
| `Ichor.Projects.GenesisTeamSpecBuilder` | Plain Module | Builds team specs for Genesis mode runs. |
| `Ichor.Projects.Graph` | Plain Module | Pure DAG algorithms and graph transforms. |
| `Ichor.Projects.HealthChecker` | Plain Module | Performs run-level DAG health checks. |
| `Ichor.Projects.HealthReport` | Plain Module | Executes and shapes DAG runtime health reports. |
| `Ichor.Projects.Janitor` | GenServer | Monitors run processes and cleans orphaned team/session state. |
| `Ichor.Projects.Job` | Ash Resource | Claimable DAG execution unit. |
| `Ichor.Projects.LifecycleSupervisor` | Supervisor | Root supervisor for the MES subsystem. |
| `Ichor.Projects.Loader` | Plain Module | Loads `Run` and `Job` data from Genesis or `tasks.jsonl`. |
| `Ichor.Projects.ModePrompts` | Plain Module | Prompt templates for Genesis planning teams. |
| `Ichor.Projects.ModeSpawner` | Plain Module | Spawns Genesis mode teams in tmux. |
| `Ichor.Projects.Node` | Ash Resource | Genesis node representing a subsystem across stages. |
| `Ichor.Projects.Phase` | Ash Resource | Mode C roadmap phase. |
| `Ichor.Projects.PipelineStage` | Plain Module | Derives a node's current stage from loaded associations. |
| `Ichor.Projects.PlanRunner` | GenServer | Owns one Genesis mode run lifecycle. |
| `Ichor.Projects.PlanSupervisor` | Supervisor | Supervises Genesis plan-run processes. |
| `Ichor.Projects.ProjectIngestor` | GenServer | Watches messages/signals to detect MES project briefs. |
| `Ichor.Projects.Project` | Ash Resource | MES-produced subsystem brief. |
| `Ichor.Projects.ResearchContext` | Plain Module | Builds research context for MES prompts from Memories data. |
| `Ichor.Projects.ResearchIngestor` | GenServer | Pushes MES project data into Memories. |
| `Ichor.Projects.ResearchStore` | Plain Module | Read-only access to Memories for project research. |
| `Ichor.Projects.RoadmapTask` | Ash Resource | Mode C roadmap task. |
| `Ichor.Projects.RunProcess` | GenServer | Owns one live DAG execution run lifecycle. |
| `Ichor.Projects.RunSupervisor` | Plain Module | Facade for starting/querying run-process children. |
| `Ichor.Projects.Run` | Ash Resource | DAG execution session/resource. |
| `Ichor.Projects.RunnerRegistry` | Plain Module | Shared registry helper for MES and DAG run processes. |
| `Ichor.Projects.Runtime` | GenServer | Live DAG runtime behind project discovery, refresh, and repair actions. |
| `Ichor.Projects.RuntimeCallbacks` | Plain Module | Boundary for runtime side effects from state transitions. |
| `Ichor.Projects.RuntimeSignals` | Plain Module | Centralizes DAG signal emission. |
| `Ichor.Projects.Scheduler` | GenServer | Ticks MES scheduling and starts build runs. |
| `Ichor.Projects.Section` | Ash Resource | Mode C roadmap section. |
| `Ichor.Projects.Spawner` | Plain Module | High-level DAG team/run spawner. |
| `Ichor.Projects.SubsystemLoader` | Plain Module | Compiles and hot-loads generated subsystem Mix projects. |
| `Ichor.Projects.SubsystemScaffold` | Plain Module | Creates standalone Mix projects for subsystems. |
| `Ichor.Projects.Subtask` | Ash Resource | Atomic roadmap execution unit. |
| `Ichor.Projects.TeamCleanup` | Plain Module | MES-specific cleanup policy over generic lifecycle helpers. |
| `Ichor.Projects.TeamLifecycle` | Plain Module | MES launch/cleanup orchestration wrapper. |
| `Ichor.Projects.TeamPrompts` | Plain Module | Prompt builders for MES team roles. |
| `Ichor.Projects.TeamSpecBuilder` | Plain Module | Builds team specs for MES runs. |
| `Ichor.Projects.Types.WorkStatus` | Plain Module | Ash enum type for Genesis work status. |
| `Ichor.Projects.UseCase` | Ash Resource | Genesis use-case artifact. |
| `Ichor.Projects.Validator` | Plain Module | Detects cycles and missing refs in DAG definitions. |
| `Ichor.Projects.WorkerGroups` | Plain Module | Groups jobs by shared file ownership into workers. |

### `/lib/ichor/projects/job/preparations`

Preparations attached to DAG job read actions.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Projects.Job.Preparations.FilterAvailable` | Ash Preparation | Filters available jobs after query execution. |

### `/lib/ichor/projects/subsystem_scaffold`

Template support for generated subsystem projects.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Projects.SubsystemScaffold.Templates` | Plain Module | Renders files/templates for generated Mix projects. |

### `/lib/ichor/projects/types`

Custom Ash types for the projects domain.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Projects.Types.WorkStatus` | Plain Module | Enumerates `pending`, `in_progress`, `completed`, `blocked`. |

## `/lib/ichor/signals`

Signal bus implementation and catalog.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Signals.Buffer` | GenServer | Buffers recent signals and rebroadcasts feed updates. |
| `Ichor.Signals.Catalog` | Plain Module | Declares every valid signal and its payload contract. |
| `Ichor.Signals.Event` | Ash Resource | Exposes signal actions to Archon/tools. |
| `Ichor.Signals.FromAsh` | Plain Module | Ash notifier translating resource mutations into signals. |
| `Ichor.Signals.Runtime` | Plain Module | Runtime implementation for emit/subscribe/unsubscribe and PubSub fan-out. |

### `/lib/ichor/signals/catalog`

Grouped signal-definition catalogs.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Signals.Catalog.GatewayAgentDefs` | Plain Module | Defines gateway and agent runtime signals. |
| `Ichor.Signals.Catalog.GenesisDagDefs` | Plain Module | Defines Genesis and DAG lifecycle signals. |
| `Ichor.Signals.Catalog.MesDefs` | Plain Module | Defines MES scheduler/run/project signals. |

## `/lib/ichor/tasks`

Team task storage and mutation helpers.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Tasks.Board` | Plain Module | Task-board CRUD facade with signal emission. |
| `Ichor.Tasks.JsonlStore` | Plain Module | In-place mutation of DAG `tasks.jsonl` files. |
| `Ichor.Tasks.TeamStore` | Plain Module | Filesystem-backed per-team task persistence. |

## `/lib/ichor/tools`

MCP-facing surfaces. These are Ash resources because AshAi exposes them as tool actions.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Tools.AgentControl` | Plain Module | Shared runtime control helpers used by tool resources. |
| `Ichor.Tools.GenesisFormatter` | Plain Module | Normalizes Genesis tool inputs and response shapes. |
| `Ichor.Tools.Profiles` | Plain Module | Chooses which tools each MCP endpoint exposes. |

### `/lib/ichor/tools/agent`

Agent-facing tool resources.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Tools.Agent.Agents` | Ash Resource | Agent registration/listing tools. |
| `Ichor.Tools.Agent.Archival` | Ash Resource | Archival memory insert/search tools. |
| `Ichor.Tools.Agent.DagExecution` | Ash Resource | DAG claim/completion/status/file-sync tools. |
| `Ichor.Tools.Agent.GenesisArtifacts` | Ash Resource | Genesis artifact create/list tools. |
| `Ichor.Tools.Agent.GenesisGates` | Ash Resource | Checkpoint and design-conversation tools. |
| `Ichor.Tools.Agent.GenesisNodes` | Ash Resource | Genesis node lifecycle tools. |
| `Ichor.Tools.Agent.GenesisRoadmap` | Ash Resource | Phase/section/task/subtask tools. |
| `Ichor.Tools.Agent.Inbox` | Ash Resource | Agent inbox/read/ack/send tools. |
| `Ichor.Tools.Agent.Memory` | Ash Resource | Core memory read/edit tools. |
| `Ichor.Tools.Agent.Recall` | Ash Resource | Memory/recall search tools. |
| `Ichor.Tools.Agent.Spawn` | Ash Resource | Observable tmux-backed agent spawn tool. |
| `Ichor.Tools.Agent.Tasks` | Ash Resource | Task-board query/update tools. |

### `/lib/ichor/tools/archon`

Archon-facing tool resources.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `Ichor.Tools.Archon.Agents` | Ash Resource | Fleet agent queries. |
| `Ichor.Tools.Archon.Control` | Ash Resource | Spawn/stop/pause/resume fleet control actions. |
| `Ichor.Tools.Archon.Events` | Ash Resource | Event feed and task overview tools. |
| `Ichor.Tools.Archon.Manager` | Ash Resource | Manager snapshot and attention-query tools. |
| `Ichor.Tools.Archon.Memory` | Ash Resource | Memories graph search and ingest tools. |
| `Ichor.Tools.Archon.Mes` | Ash Resource | MES project/scheduler/operator-floor tools. |
| `Ichor.Tools.Archon.Messages` | Ash Resource | Recent message read and operator-send tools. |
| `Ichor.Tools.Archon.System` | Ash Resource | System diagnostics and tmux health tools. |
| `Ichor.Tools.Archon.Teams` | Ash Resource | Team query tools. |

## Web entrypoints outside `lib/ichor`

These modules are not part of the `lib/ichor` tree, but they matter for the architecture requested in `ARCHITECTURE.md`.

| Module | Type | Responsibilities |
| --- | --- | --- |
| `IchorWeb.Router` | Component | Phoenix router; maps HTTP, MCP, gateway, and LiveView routes into the runtime. |
| `IchorWeb.DashboardLive` | LiveView | Main operator UI; subscribes to signals and dispatches fleet/MES/DAG actions. |
| `IchorWeb.*Controller` modules | Controller | HTTP APIs for events, gateway, HITL, export, heartbeat, debug, and webhooks. |

`IchorWeb.Router` is listed as `Component` here only because the requested classification set does not include a router category. In practice, treat it as the Phoenix routing boundary rather than a UI component.
