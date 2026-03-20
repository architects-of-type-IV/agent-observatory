# ICHOR IV Module Index

Quick reference for the `lib/ichor` tree. This index is intentionally terse; see `MODULES.md` for classification and responsibilities, and `ARCHITECTURE.md` for system flow.

## Root

- `Ichor.AgentWatchdog` - Consolidated health monitor for agents, heartbeats, nudges, and pane-derived completion signals.
- `Ichor.Application` - OTP application entrypoint that boots infrastructure, supervisors, subsystems, and the Phoenix endpoint.
- `Ichor.Architecture.BoundaryAudit` - Static audit helper for checking architectural boundary violations.
- `Ichor.Control` - Ash domain for the fleet control plane.
- `Ichor.EventBuffer` - In-memory event buffer used for timelines, projections, and dashboard state.
- `Ichor.MemoriesBridge` - Bridges Ichor signals into the external Memories knowledge graph.
- `Ichor.MemoryStore` - Local three-tier memory system for agent memory blocks, archival, and recall.
- `Ichor.Notes` - ETS-backed note store for operator annotations.
- `Ichor.Observability` - Ash domain for events, messages, errors, sessions, and tasks.
- `Ichor.ObservationSupervisor` - Supervises observation-side services such as the causal DAG and event bridge.
- `Ichor.Plugs.OperatorAuth` - Plug that validates operator identity for HITL endpoints.
- `Ichor.Projects` - Ash domain for Genesis, MES, and DAG execution flows.
- `Ichor.ProtocolTracker` - Correlates messages across transport layers into end-to-end traces.
- `Ichor.QualityGate` - Enforces task completion quality gates and corrective nudges.
- `Ichor.Repo` - Ecto repository for SQLite-backed Ash resources.
- `Ichor.SystemSupervisor` - Supervisor for independent core, gateway, monitoring, and Archon services.
- `Ichor.Tasks.Board` - Unified task-board action layer with signal emission.
- `Ichor.Tasks.JsonlStore` - In-place mutation helpers for `tasks.jsonl`.
- `Ichor.Tasks.TeamStore` - File-backed per-team task storage under `~/.claude/tasks`.
- `Ichor.Tools` - Ash domain exposing MCP tool surfaces for agents and Archon.

## `agent_watchdog`

- `Ichor.AgentWatchdog.EventState` - Pure reducers for per-session activity tracking.
- `Ichor.AgentWatchdog.NudgePolicy` - Pure stale-agent escalation policy helpers.
- `Ichor.AgentWatchdog.PaneParser` - Pure tmux pane diffing and signal extraction helpers.

## `archon`

- `Ichor.Archon.Chat` - Stateless Archon conversation entrypoint for slash commands and LLM turns.
- `Ichor.Archon.CommandManifest` - Source of truth for Archon slash command metadata.
- `Ichor.Archon.MemoriesClient` - Req-based client for the Memories graph API.
- `Ichor.Archon.SignalManager` - Signal-fed managerial state and attention queue for Archon.
- `Ichor.Archon.TeamWatchdog` - Signal-driven watchdog for run completion, resets, and operator notifications.

### `archon/chat`

- `Ichor.Archon.Chat.ChainBuilder` - Builds the Archon LangChain pipeline and mounts tool resources.
- `Ichor.Archon.Chat.CommandRegistry` - Maps parsed slash commands to Ash actions and typed responses.
- `Ichor.Archon.Chat.ContextBuilder` - Retrieves memory context snippets for Archon turns.
- `Ichor.Archon.Chat.TurnRunner` - Executes a single LLM-backed Archon turn.

## `control`

- `Ichor.Control.Agent` - Canonical Ash entrypoint for live agent reads and lifecycle actions.
- `Ichor.Control.AgentBlueprint` - Persisted agent node used by the Workshop builder.
- `Ichor.Control.AgentProcess` - BEAM-native live agent process with mailbox and pluggable delivery backend.
- `Ichor.Control.AgentType` - Reusable agent archetype defaults for Workshop and presets.
- `Ichor.Control.BlueprintState` - Pure state transitions for the Workshop canvas.
- `Ichor.Control.CommRule` - Persisted communication rule between agent blueprints.
- `Ichor.Control.FleetSupervisor` - Root dynamic supervisor for teams and standalone agents.
- `Ichor.Control.HostRegistry` - Tracks available BEAM hosts via `:pg`.
- `Ichor.Control.Lookup` - Shared lookup helpers for teams and agents.
- `Ichor.Control.Presets` - Canonical Workshop presets and launch ordering.
- `Ichor.Control.RuntimeQuery` - Read-model queries over teams, sessions, events, and tasks.
- `Ichor.Control.RuntimeView` - Display projections for team and agent runtime state.
- `Ichor.Control.SpawnLink` - Persisted spawn hierarchy edge between blueprints.
- `Ichor.Control.Team` - Canonical Ash entrypoint for live team reads and team lifecycle actions.
- `Ichor.Control.TeamBlueprint` - Persisted Workshop team blueprint.
- `Ichor.Control.TeamSpecBuilder` - Builds runtime `TeamSpec` and `AgentSpec` values from Workshop state.
- `Ichor.Control.TeamSupervisor` - Dynamic supervisor for one team's `AgentProcess` children.
- `Ichor.Control.TmuxHelpers` - Shared helpers for tmux-backed spawning.
- `Ichor.Control.Types.HealthStatus` - Ash enum type for agent/team health.

### `control/agent_process`

- `Ichor.Control.AgentProcess.Delivery` - Normalizes messages and dispatches them to tmux, SSH, or webhook backends.
- `Ichor.Control.AgentProcess.Lifecycle` - Liveness polling and lifecycle helpers for agents.
- `Ichor.Control.AgentProcess.Mailbox` - Mailbox buffering, broadcast, and routing helpers.
- `Ichor.Control.AgentProcess.Registry` - Registry metadata shaping for agent processes.

### `control/analysis`

- `Ichor.Control.Analysis.AgentHealth` - Computes health, stuckness, and loop warnings from events.
- `Ichor.Control.Analysis.Queries` - Pure fleet/session/task projection helpers.
- `Ichor.Control.Analysis.SessionEviction` - Evicts events for stale sessions from projections.

### `control/lifecycle`

- `Ichor.Control.Lifecycle.AgentLaunch` - Spawns and stops individual tmux-backed agents.
- `Ichor.Control.Lifecycle.AgentSpec` - Data contract for one launched agent.
- `Ichor.Control.Lifecycle.Cleanup` - Cleanup helpers for sessions, agents, and teams.
- `Ichor.Control.Lifecycle.Registration` - Registers tmux-backed agents and teams into the fleet.
- `Ichor.Control.Lifecycle.TeamLaunch` - Launches and tears down multi-agent tmux sessions.
- `Ichor.Control.Lifecycle.TeamSpec` - Data contract for a launched multi-agent team.
- `Ichor.Control.Lifecycle.TmuxLauncher` - Creates, destroys, and probes tmux sessions and windows.
- `Ichor.Control.Lifecycle.TmuxScript` - Materializes prompt and launch script files for tmux sessions.

### `control/views/preparations`

- `Ichor.Control.Views.Preparations.LoadAgents` - Ash preparation that projects live agents from registry state.
- `Ichor.Control.Views.Preparations.LoadTeams` - Ash preparation that projects live teams from registry state and recent events.

## `gateway`

- `Ichor.Gateway.Channel` - Behaviour for delivery channel adapters.
- `Ichor.Gateway.CronJob` - Ash resource for scheduled cron jobs.
- `Ichor.Gateway.CronScheduler` - Schedules and executes one-off or recurring cron work.
- `Ichor.Gateway.EntropyTracker` - Detects loops via sliding-window session entropy.
- `Ichor.Gateway.Envelope` - Normalized gateway message envelope.
- `Ichor.Gateway.EventBridge` - Bridges ingested hook events into gateway message traffic.
- `Ichor.Gateway.HeartbeatManager` - Tracks heartbeats and agent liveness timeouts.
- `Ichor.Gateway.HITLInterventionEvent` - Ash resource recording HITL interventions.
- `Ichor.Gateway.HITLRelay` - Manages HITL pause/unpause/rewrite/inject lifecycle by session.
- `Ichor.Gateway.IntentMapper` - Maps gateway envelopes to delivery intents.
- `Ichor.Gateway.OutputCapture` - Polls tmux output for watched agents and broadcasts deltas.
- `Ichor.Gateway.Router` - Central message router for gateway traffic.
- `Ichor.Gateway.SchemaInterceptor` - Validation gate for inbound gateway messages.
- `Ichor.Gateway.TmuxDiscovery` - Discovers tmux sessions and keeps fleet/runtime invariants aligned.
- `Ichor.Gateway.TopologyBuilder` - Publishes topology snapshots onto PubSub.
- `Ichor.Gateway.WebhookDelivery` - Ash resource tracking webhook retries and dead-letter state.
- `Ichor.Gateway.WebhookRouter` - Durable webhook delivery worker with backoff and dead-letter handling.

### `gateway/agent_registry`

- `Ichor.Gateway.AgentRegistry.AgentEntry` - Shared agent-map constructor and helper functions.

### `gateway/channels`

- `Ichor.Gateway.Channels.AnsiUtils` - ANSI escape code helpers for channel output processing.
- `Ichor.Gateway.Channels.MailboxAdapter` - Delivers through live `AgentProcess` mailboxes.
- `Ichor.Gateway.Channels.SshTmux` - Delivers into tmux on remote hosts over SSH.
- `Ichor.Gateway.Channels.Tmux` - Delivers into local tmux sessions using named buffers.
- `Ichor.Gateway.Channels.WebhookAdapter` - Enqueues durable webhook-based delivery.

## `memory_store`

- `Ichor.MemoryStore.Persistence` - Disk persistence helpers for memory snapshots.
- `Ichor.MemoryStore.Storage` - All ETS operations: block CRUD, agent CRUD, recall, and archival.

## `mesh`

- `Ichor.Mesh.CausalDAG` - ETS-backed causal DAG per active session.
- `Ichor.Mesh.DecisionLog` - Ecto schema for the universal inter-agent decision log envelope.

### `mesh/decision_log`

- `Ichor.Mesh.DecisionLog.Helpers` - Helper functions for decision-log construction and querying.

## `observability`

- `Ichor.Observability.Error` - Tool error projection derived from failure hook events.
- `Ichor.Observability.Event` - Canonical stored hook event resource.
- `Ichor.Observability.EventAnalysis` - Event analytics and timeline helpers.
- `Ichor.Observability.Janitor` - Purges old SQLite observability rows.
- `Ichor.Observability.Message` - Inter-agent message projection derived from hook events.
- `Ichor.Observability.Session` - Session projection/resource for observability queries.
- `Ichor.Observability.Task` - Task projection derived from task hook events.

### `observability/preparations`

- `Ichor.Observability.Preparations.EventBufferReader` - Shared event-buffer read helper for preparations.
- `Ichor.Observability.Preparations.LoadErrors` - Loads error projections from buffered events.
- `Ichor.Observability.Preparations.LoadMessages` - Loads message projections from buffered events.
- `Ichor.Observability.Preparations.LoadTasks` - Loads task projections from buffered events.

## `projects`

- `Ichor.Projects.Actions` - Task mutation and corrective actions for the live DAG runtime.
- `Ichor.Projects.Artifact` - Genesis artifact resource for mode-produced deliverables.
- `Ichor.Projects.Catalog` - Project discovery/selection helpers for DAG runtime state.
- `Ichor.Projects.CompletionHandler` - Reacts to DAG completion by compiling and loading subsystems.
- `Ichor.Projects.DagAnalysis` - Parses tasks and derives DAG runtime projections.
- `Ichor.Projects.DagGenerator` - Builds DAG jobs from Genesis roadmap hierarchy.
- `Ichor.Projects.DagPrompts` - Prompt templates for DAG coordinator/lead/worker teams.
- `Ichor.Projects.DagTeamSpecBuilder` - Builds `TeamSpec` values for DAG execution teams.
- `Ichor.Projects.DateUtils` - Date/time formatting and comparison helpers.
- `Ichor.Projects.Discovery` - Discovers DAG-capable projects and archives on disk.
- `Ichor.Projects.Exporter` - Syncs DAG jobs back to `tasks.jsonl`.
- `Ichor.Projects.GenesisTeamSpecBuilder` - Builds `TeamSpec` values for Genesis planning teams.
- `Ichor.Projects.Graph` - Pure DAG algorithms on normalized graph nodes.
- `Ichor.Projects.HealthChecker` - Health checks for active DAG runs.
- `Ichor.Projects.HealthReport` - Executes health checks and shapes runtime health reports.
- `Ichor.Projects.Janitor` - Monitors run processes and cleans orphaned team/session resources.
- `Ichor.Projects.Job` - Claimable DAG execution unit resource.
- `Ichor.Projects.LifecycleSupervisor` - Root supervisor for the MES subsystem.
- `Ichor.Projects.Loader` - Loads DAG runs/jobs from `tasks.jsonl` or Genesis hierarchy.
- `Ichor.Projects.ModePrompts` - Prompt templates for Genesis planning teams.
- `Ichor.Projects.ModeSpawner` - Spawns Genesis planning teams in tmux.
- `Ichor.Projects.Node` - Genesis node resource tracking a subsystem through modes.
- `Ichor.Projects.PipelineStage` - Derives current pipeline stage from node associations.
- `Ichor.Projects.Project` - MES-generated subsystem project brief resource.
- `Ichor.Projects.ProjectIngestor` - Detects project briefs arriving from MES teams.
- `Ichor.Projects.ResearchContext` - Builds Memories-backed context for MES research prompts.
- `Ichor.Projects.ResearchIngestor` - Ingests MES briefs into the Memories graph.
- `Ichor.Projects.ResearchStore` - Read-only interface to Memories for project research.
- `Ichor.Projects.RoadmapItem` - Roadmap item resource for Genesis planning hierarchy.
- `Ichor.Projects.Run` - DAG execution session resource.
- `Ichor.Projects.Runner` - Unified GenServer for MES, Genesis, and DAG run lifecycles.
- `Ichor.Projects.Runtime` - Live DAG runtime process behind discovery, refresh, and repair actions.
- `Ichor.Projects.RuntimeCallbacks` - Boundary for side effects triggered by DAG runtime transitions.
- `Ichor.Projects.RuntimeSignals` - Centralized signal emission for DAG runtime events.
- `Ichor.Projects.Scheduler` - MES scheduler that ticks and starts build runs.
- `Ichor.Projects.Spawn` - Low-level team spawn helpers for DAG runs.
- `Ichor.Projects.Spawner` - Spawns a full DAG execution team and run process.
- `Ichor.Projects.SubsystemLoader` - Compiles and hot-loads generated subsystem projects.
- `Ichor.Projects.SubsystemScaffold` - Creates standalone Mix projects for subsystems.
- `Ichor.Projects.TeamCleanup` - MES cleanup policy layered on generic lifecycle helpers.
- `Ichor.Projects.TeamPrompts` - Prompt builders for MES team roles.
- `Ichor.Projects.TeamSpec` - Data contract for a projects-domain team launch.
- `Ichor.Projects.TeamSpecBuilder` - Builds `TeamSpec` values for MES teams.
- `Ichor.Projects.Types.WorkStatus` - Ash enum type for Genesis work status.
- `Ichor.Projects.Validator` - Preflight DAG validation helpers.
- `Ichor.Projects.WorkerGroups` - Groups jobs by shared file ownership into workers.

### `projects/job`

- `Ichor.Projects.Job.Changes.SyncRunProcess` - Ash change that syncs job state to the run process.
- `Ichor.Projects.Job.Preparations.FilterAvailable` - Post-query filter backing the `Job.available/1` read action.

## `signals`

- `Ichor.Signals.Buffer` - Ring buffer and PubSub feed for all emitted signals.
- `Ichor.Signals.Catalog` - Source of truth for valid signals, categories, and payload keys.
- `Ichor.Signals.Event` - Ash action surface for querying and emitting signals.
- `Ichor.Signals.FromAsh` - Ash notifier that turns resource mutations into signals.
- `Ichor.Signals.Runtime` - Runtime implementation of signal emission, subscription, and PubSub fan-out.

## `tools`

- `Ichor.Tools.AgentMemory` - Agent memory read/write tool resource.
- `Ichor.Tools.Archon.Memory` - Knowledge-graph memory search and ingest tools for Archon.
- `Ichor.Tools.Genesis` - Genesis workflow tool resource.
- `Ichor.Tools.Profiles` - MCP profile lists deciding which tools each endpoint exposes.
- `Ichor.Tools.ProjectExecution` - DAG project execution tool resource.
- `Ichor.Tools.RuntimeOps` - Runtime operations tool resource.
