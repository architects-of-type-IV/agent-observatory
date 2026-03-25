 # lib/ichor/ Module Tree

Updated 2026-03-25 after ADR-026 Signal pipeline, Infrastructure reorg, and module consolidation.

```
lib/ichor/
├── application.ex                 # OTP application entry point, supervision tree root
├── discovery.ex                   # Planned: expose Ash actions by Domain for UI composition
├── mcp_profiles.ex                # MCP tool profile definitions
├── memory_store.ex                # Letta-compatible three-tier agent memory (blocks, recall, archival)
├── notes.ex                       # ETS-backed operator annotation store
├── pub_sub.ex                     # PubSub configuration constants
├── repo.ex                        # Ecto repository (PostgreSQL)
├── runtime_supervisor.ex          # Shared runtime: Registry, ProcessSupervisor, PubSub bridge
├── signal.ex                      # `use Ichor.Signal` macro -- declarative signal module definition
│
├── archon/                        # App manager agent (Archon domain)
│   ├── chat.ex                    # LLM-backed Archon conversation engine
│   ├── command_manifest.ex        # Archon MCP command metadata (source of truth)
│   ├── manager.ex                 # Ash action surface for Archon control
│   └── memory.ex                  # Ash resource for Archon memory access
│
├── events/                        # Domain event pipeline (ADR-026 producer side)
│   ├── event.ex                   # %Event{} struct -- single envelope used everywhere
│   ├── from_ash.ex                # Ash notifier: bridges Ash actions -> Event pipeline
│   ├── ingress.ex                 # GenStage producer: receives events, buffers for downstream
│   ├── stored_event.ex            # Ash resource: append-only durable event log (PostgreSQL)
│   └── topic_mapping.ex           # Maps legacy atom signal names -> dot-delimited topics
│
├── factory/                       # MES project planning + pipeline execution domain
│   ├── artifact.ex                # Embedded SDLC artifact
│   ├── board.ex                   # Board state Ash resource
│   ├── completion_handler.ex      # DAG completion signal handler
│   ├── cron_job.ex                # Durable cron job Ash resource
│   ├── floor.ex                   # Factory operator control action surface
│   ├── jsonl_store.ex             # JSONL file read/write helpers
│   ├── lifecycle_supervisor.ex    # Factory lifecycle supervisor
│   ├── loader.ex                  # Loads project/pipeline data from Genesis or disk
│   ├── mes_scheduler.ex           # MES scheduler API: pause/resume/status (Oban-backed tick)
│   ├── pipeline.ex                # Pipeline Ash resource
│   ├── pipeline_compiler.ex       # Roadmap -> DAG pipeline compilation
│   ├── pipeline_graph.ex          # Pure pipeline graph computation
│   ├── pipeline_query.ex          # Pure pipeline board state + mutations
│   ├── pipeline_task.ex           # Executable pipeline task Ash resource
│   ├── planning_prompts.ex        # Planning team prompt templates
│   ├── plugin_loader.ex           # Loads generated plugin projects into BEAM
│   ├── plugin_scaffold.ex         # Creates plugin project directory structure
│   ├── project.ex                 # Durable MES project Ash resource
│   ├── project_stage.ex           # Project stage derivation helpers
│   ├── project_view.ex            # Project view helpers
│   ├── research_context.ex        # Research context builder
│   ├── roadmap_item.ex            # Embedded planning tree item
│   ├── run_ref.ex                 # Typed run reference struct (kind + run_id)
│   ├── runner.ex                  # MES/pipeline run lifecycle GenServer
│   ├── runner/
│   │   ├── exporter.ex            # Run export helpers
│   │   ├── health_checker.ex      # Run health check helpers
│   │   └── modes.ex               # Mode-specific runner builders
│   ├── spawn.ex                   # Planning/pipeline team launch + cleanup
│   ├── validator.ex               # Pipeline structure validation
│   ├── worker_groups.ex           # Worker group builder for pipeline spawns
│   └── workers/
│       ├── archive_run_worker.ex              # Oban: archive completed pipeline run (AD-8)
│       ├── health_check_worker.ex             # Oban cron: pipeline health check
│       ├── mes_tick.ex                        # Oban cron: MES scheduler tick
│       ├── orphan_sweep_worker.ex             # Oban cron: orphan team cleanup
│       ├── pipeline_reconciler_worker.ex      # Oban cron: detect orphaned pipelines (AD-8 safety net)
│       ├── project_discovery_worker.ex        # Oban cron: scan directories for new projects
│       └── reset_run_tasks_worker.ex          # Oban: reset in_progress tasks on crash (AD-8)
│
├── infrastructure/                # Host layer: adapters, fleet processes, runtime
│   ├── agent_backend.ex           # Selects delivery backend for an agent (tmux/webhook/mailbox)
│   ├── agent_delivery.ex          # Delivers messages to an agent via its backend
│   ├── agent_launch.ex            # Lifecycle operations for individual agent start/stop
│   ├── agent_message.ex           # Agent message Ash resource
│   ├── agent_process.ex           # BEAM GenServer per live agent (mailbox, liveness polling)
│   ├── agent_registry_projection.ex # Builds/derives ETS registry metadata for agent processes
│   ├── agent_spec.ex              # Generic runtime agent spec struct
│   ├── agent_state.ex             # Agent state Ash resource
│   ├── ansi_utils.ex              # ANSI escape -> HTML rendering
│   ├── channel.ex                 # Channel behaviour (tmux, webhook, mailbox)
│   ├── cleanup.ex                 # Runtime cleanup: kill tmux sessions, remove files
│   ├── cron_scheduler.ex          # Cron scheduling API (Oban-backed)
│   ├── fleet_supervisor.ex        # DynamicSupervisor for teams and standalone agents
│   ├── hitl_relay.ex              # HITL pause/unpause lifecycle GenServer with ETS buffer
│   ├── hitl/
│   │   ├── buffer.ex              # ETS buffer for messages while session is paused
│   │   └── session_state.ex       # HITL per-session pause state
│   ├── host_registry.ex           # ETS registry for BEAM cluster nodes
│   ├── memories_client.ex         # HTTP client for external Memories knowledge graph API
│   ├── operations.ex              # Ash action surface for infrastructure operations
│   ├── output_capture.ex          # Polls tmux pane output
│   ├── plugs/
│   │   └── operator_auth.ex       # Phoenix plug: validates operator auth header
│   ├── registration.ex            # Agent/team BEAM Registry registration helpers
│   ├── team_launch.ex             # Orchestrates full team launch (prompts -> tmux -> registration)
│   ├── team_launch/
│   │   └── session.ex             # Creates tmux session and windows during team launch
│   ├── team_spec.ex               # Generic runtime team spec struct
│   ├── team_supervisor.ex         # Per-team DynamicSupervisor
│   ├── tmux.ex                    # Tmux runtime adapter
│   ├── tmux/
│   │   ├── command.ex             # Builds tmux CLI commands
│   │   ├── launcher.ex            # Creates tmux sessions and windows
│   │   ├── script.ex              # Generates agent launch scripts
│   │   └── server_selector.ex     # Selects the target tmux server
│   ├── tmux_discovery.ex          # Discovers active tmux sessions
│   ├── webhook_adapter.ex         # Webhook HTTP delivery adapter
│   ├── webhook_delivery.ex        # Durable webhook delivery Ash resource
│   └── workers/
│       ├── scheduled_job.ex               # Oban: fire a scheduled cron job
│       ├── session_cleanup_worker.ex      # Oban: kill tmux session or disband fleet team
│       └── webhook_delivery_worker.ex     # Oban: deliver webhook with retry
│
├── memory_store/
│   ├── persistence.ex             # Disk persistence layer for memory store
│   └── storage.ex                 # ETS-level memory store read/write operations
│
├── operator/
│   └── inbox.ex                   # Writes messages to agent inbox files on disk
│
├── projector/                     # Signal-driven GenServer projectors (react to Signals domain)
│   ├── agent_watchdog.ex          # Consolidated health monitor: heartbeat, crash detection, escalation, pane scan
│   ├── agent_watchdog/
│   │   ├── escalation_engine.ex   # Progressive nudge/pause/zombie escalation logic
│   │   └── pane_scanner.ex        # Scans tmux panes for DONE/BLOCKED markers
│   ├── cleanup_dispatcher.ex      # Routes :cleanup signals -> Oban workers (archive, reset, disband, kill)
│   ├── fleet_lifecycle.ex         # Reacts to :fleet signals -> spawn/terminate AgentProcess + TeamSupervisor
│   ├── mes_project_ingestor.ex    # Detects MES project payloads in messages, creates Factory.Project
│   ├── mes_research_ingestor.ex   # On :mes_project_created, ingests brief artifact into Memories
│   ├── protocol_tracker.ex        # Correlates multi-protocol message traces in ETS
│   ├── signal_buffer.ex           # Ring buffer (200 entries) for all signals; re-broadcasts on "signals:feed"
│   ├── signal_manager.ex          # Archon's signal-fed state: compact attention queue, severity tracking
│   └── team_watchdog.ex           # Detects unexpected team deaths, dispatches :cleanup signals
│
├── settings/                      # Settings Ash domain
│   ├── settings_project.ex        # SettingsProject Ash resource (registered projects)
│   └── settings_project/
│       ├── git_info.ex            # Embedded git info (branch, commit, dirty)
│       └── location.ex            # Embedded filesystem location
│
├── signals/                       # Reactive backbone: ADR-026 GenStage pipeline
│   ├── action_handler.ex          # Dispatches Signal activations to system actions (HITL, Bus, log)
│   ├── behaviour.ex               # Signal module behaviour contract (6 callbacks)
│   ├── bus.ex                     # Single message delivery authority
│   ├── catalog.ex                 # Declarative signal catalog with category metadata
│   ├── checkpoint.ex              # Ash resource: tracks last processed event per signal (crash resume)
│   ├── event_stream.ex            # ETS event buffer + liveness tracking (canonical event owner)
│   ├── event_stream/
│   │   ├── agent_lifecycle.ex     # Signal emission helpers for agent lifecycle events
│   │   └── normalizer.ex          # Normalizes raw hook events into %Event{} structs
│   ├── hitl_intervention_event.ex # Ash resource: durable HITL audit record
│   ├── message.ex                 # Signal message struct
│   ├── operations.ex              # Ash action surface for messaging and signal operations
│   ├── pipeline_supervisor.ex     # Supervises Ingress (producer) + Router (consumer) with rest_for_one
│   ├── router.ex                  # GenStage consumer: routes events to SignalProcess instances by topic
│   ├── runtime.ex                 # Signal transport: envelope building, catalog validation, PubSub broadcast
│   ├── signal.ex                  # %Signal{} struct (accumulated events that triggered a flush)
│   ├── signal_process.ex          # Stateful accumulator GenServer per {signal_module, key}
│   ├── topics.ex                  # PubSub topic string constants
│   └── agent/
│       ├── entropy.ex             # Signal: sliding-window loop detection per session
│       ├── message_protocol.ex    # Signal: checks messages against team comm_rules
│       └── tool_budget.ex         # Signal: fires when tool calls exceed session limit
│
└── workshop/                      # Agent + team design domain
    ├── active_team.ex             # Read action surface for active teams (ETS-backed)
    ├── agent.ex                   # Read action surface for live agents (ETS-backed)
    ├── agent_def.ex               # Persisted agent definition Ash resource (belongs to AgentType)
    ├── agent_entry.ex             # Agent entry struct with UUID detection and short_id
    ├── agent_id.ex                # Typed agent identifier: parses structured session ID strings
    ├── agent_memory.ex            # Workshop memory action surface
    ├── agent_slot.ex              # Agent slot Ash resource (position in team blueprint)
    ├── agent_type.ex              # Reusable agent archetype Ash resource
    ├── analysis/
    │   ├── agent_health.ex        # Computes agent health scores
    │   └── queries.ex             # Fleet/team analytics queries
    ├── canvas_state.ex            # Workshop editor state transitions
    ├── comm_rule.ex               # Communication rule Ash resource (deny/allow between slots)
    ├── pipeline_prompts.ex        # Prompt templates for pipeline worker teams
    ├── preparations/
    │   ├── load_agents.ex         # Ash preparation: loads agent data from ETS
    │   └── load_teams.ex          # Ash preparation: loads team data from Registry
    ├── presets.ex                 # Workshop presets (named team blueprints)
    ├── prompt.ex                  # Prompt Ash resource
    ├── prompt_protocol.ex         # Shared prompt building behaviour (AD-6)
    ├── spawn.ex                   # Builds and launches a saved team definition by name
    ├── spawn_link.ex              # SpawnLink Ash resource
    ├── team.ex                    # Durable authored team definition (Ash resource)
    ├── team_member.ex             # Team member definition (Ash resource)
    ├── team_prompts.ex            # Prompt templates for MES team agent roles
    ├── team_spawn_handler.ex      # Signal-driven team spawn listener
    ├── team_spec.ex               # TeamSpec builder with prompt_module injection (AD-6)
    ├── team_sync.ex               # Team sync utilities
    └── types/
        └── health_status.ex       # HealthStatus Ash type
```
