 # lib/ichor/ Module Tree (179 files)

Updated 2026-03-21 after Waves 1-4. Ownership boundaries and notable modules.

```
lib/ichor/
├── application.ex                 # OTP application entry point
├── discovery.ex                   # Planned: expose Ash actions by Domain for UI composition
├── memories_bridge.ex             # Bridges signal stream into Memories knowledge graph
├── memory_store.ex                # Letta-compatible three-tier agent memory GenServer
├── mcp_profiles.ex                # MCP tool profile definitions
├── notes.ex                       # ETS-backed storage for event annotations
├── pub_sub.ex                     # PubSub configuration
├── repo.ex                        # Ecto repository for Ichor SQLite database
├── runtime_supervisor.ex          # Shared runtime services supervisor
├── signal_bus.ex                  # SignalBus Ash domain
├── util.ex                        # Shared utilities
│
├── archon/                        # App manager agent domain
│   ├── chat.ex                    # Archon conversation engine, LLM-backed
│   ├── command_manifest.ex        # Archon command metadata source of truth
│   ├── manager.ex                 # Ash action surface for Archon control
│   ├── memory.ex                  # Ash resource for Archon memory access
│   ├── signal_manager.ex          # Signal-fed managerial state for Archon
│   └── team_watchdog.ex           # Pure signal emitter, cleanup via Oban dispatchers
│
├── factory/                       # Project planning + pipeline execution domain
│   ├── artifact.ex                # Embedded SDLC artifact
│   ├── board.ex                   # Board state resource
│   ├── completion_handler.ex      # DAG completion signal handler
│   ├── cron_job.ex                # Durable cron job resource (moved from Infrastructure)
│   ├── date_utils.ex              # Date parsing helpers
│   ├── floor.ex                   # Factory operator/control actions
│   ├── jsonl_store.ex             # JSONL file read/write
│   ├── lifecycle_supervisor.ex    # Factory lifecycle supervisor
│   ├── loader.ex                  # Project loader
│   ├── mes_scheduler.ex           # MES scheduler API (pause/resume/status, tick via Oban)
│   ├── pipeline.ex                # Pipeline Ash resource
│   ├── pipeline_compiler.ex       # Roadmap -> pipeline compilation
│   ├── pipeline_graph.ex          # Pure pipeline graph functions
│   ├── pipeline_query.ex          # Pure pipeline board state + mutations (replaced PipelineMonitor)
│   ├── pipeline_task.ex           # Executable pipeline task resource
│   ├── planning_prompts.ex        # Planning team prompt templates
│   ├── plugin_loader.ex           # Loads generated plugins
│   ├── plugin_scaffold.ex         # Creates plugin project dirs
│   ├── project.ex                 # Durable MES project resource
│   ├── project_ingestor.ex        # Research -> project ingestion
│   ├── project_stage.ex           # Project stage derivation
│   ├── project_view.ex            # Project view helpers
│   ├── research_context.ex        # Research context builder
│   ├── research_ingestor.ex       # Research data ingestion
│   ├── research_store.ex          # Research persistence
│   ├── roadmap_item.ex            # Embedded planning tree item
│   ├── runner.ex                  # MES/pipeline run lifecycle GenServer
│   ├── runner/
│   │   ├── exporter.ex            # Run export helpers
│   │   ├── health_checker.ex      # Run health check helpers
│   │   └── modes.ex               # Mode-specific runner builders
│   ├── spawn.ex                   # Planning/pipeline team launch + cleanup
│   ├── subscribers/
│   │   └── run_cleanup_dispatcher.ex  # Bridges :run_cleanup_needed -> Factory Oban workers
│   ├── validator.ex               # Pipeline validation
│   ├── worker_groups.ex           # Worker group builder
│   └── workers/
│       ├── archive_run_worker.ex          # Oban: archive pipeline run (AD-8)
│       ├── health_check_worker.ex         # Oban cron: pipeline health check
│       ├── mes_tick.ex                    # Oban cron: MES scheduler tick
│       ├── orphan_sweep_worker.ex         # Oban cron: orphan team cleanup
│       ├── project_discovery_worker.ex    # Oban cron: project directory scanning
│       └── reset_run_tasks_worker.ex      # Oban: reset in_progress tasks (AD-8)
│
├── infrastructure/                # Host layer: adapters, processes, runtime
│   ├── agent_backend.ex           # Agent backend adapter
│   ├── agent_delivery.ex          # Agent message delivery
│   ├── agent_launch.ex            # Full agent launcher
│   ├── agent_lifecycle.ex         # Agent start/stop/pause lifecycle signals
│   ├── agent_message.ex           # Agent message Ash resource
│   ├── agent_process.ex           # BEAM mailbox-backed agent process
│   ├── agent_registry_projection.ex # ETS agent registry projection
│   ├── agent_spec.ex              # Generic runtime agent spec
│   ├── agent_state.ex             # Agent state resource
│   ├── ansi_utils.ex              # ANSI -> HTML rendering
│   ├── channel.ex                 # Channel behaviour
│   ├── cleanup.ex                 # Runtime cleanup (tmux kill, file cleanup)
│   ├── cron_schedule.ex           # Cron time arithmetic
│   ├── cron_scheduler.ex          # Cron scheduling API (Oban-backed)
│   ├── fleet_supervisor.ex        # DynamicSupervisor for teams + agents
│   ├── hitl_relay.ex              # HITL pause/unpause relay
│   ├── hitl/
│   │   ├── buffer.ex              # HITL message buffer
│   │   ├── events.ex              # HITL event types
│   │   └── session_state.ex       # HITL session state
│   ├── host_registry.ex           # BEAM node registry
│   ├── memories_client.ex         # HTTP client for Memories knowledge graph API
│   ├── operations.ex              # Ash action surface for infrastructure
│   ├── output_capture.ex          # Pane output poller
│   ├── plugs/
│   │   └── operator_auth.ex       # Operator auth header plug
│   ├── registration.ex            # Agent/team registration helpers
│   ├── subscribers/
│   │   ├── session_cleanup_dispatcher.ex  # Bridges :session_cleanup_needed -> Infra Oban workers
│   │   └── session_lifecycle.ex           # Reacts to session/team signals -> fleet mutations
│   ├── team_launch.ex             # Team launch/teardown runtime
│   ├── team_launch/
│   │   ├── registration.ex        # Team registration during launch
│   │   ├── rollback.ex            # Launch rollback on failure
│   │   ├── scripts.ex             # Launch script generation
│   │   └── session.ex             # Launch session management
│   ├── team_spec.ex               # Generic runtime team spec
│   ├── team_supervisor.ex         # Per-team supervisor
│   ├── tmux.ex                    # Tmux delivery/runtime adapter
│   ├── tmux/
│   │   ├── command.ex             # Tmux command builder
│   │   ├── helpers.ex             # Tmux helper functions
│   │   ├── launcher.ex            # Tmux session launcher
│   │   ├── parser.ex              # Tmux output parser
│   │   ├── script.ex              # Tmux script generator
│   │   ├── server_selector.ex     # Tmux server selection
│   │   └── ssh.ex                 # SSH tunnel for remote tmux
│   ├── tmux_discovery.ex          # Tmux session discovery
│   ├── webhook_adapter.ex         # Webhook HTTP adapter
│   ├── webhook_delivery.ex        # Durable webhook delivery resource
│   ├── webhook_router.ex          # Webhook signature + Oban enqueue API
│   └── workers/
│       ├── disband_team_worker.ex         # Oban: disband team (AD-8)
│       ├── kill_session_worker.ex         # Oban: kill tmux session (AD-8)
│       ├── scheduled_job.ex               # Oban: fire scheduled job
│       └── webhook_delivery_worker.ex     # Oban: deliver webhook with retry
│
├── memory_store/
│   ├── persistence.ex             # Disk persistence for memory store
│   └── storage.ex                 # ETS-level memory store operations
│
├── mesh/                          # Topology services
│   ├── causal_dag.ex              # Per-session causal topology DAG
│   ├── decision_log.ex            # Causal message envelope (embedded)
│   ├── decision_log/
│   │   └── helpers.ex             # DecisionLog pure helpers
│   ├── event_bridge.ex            # Event -> mesh topology bridge
│   └── supervisor.ex              # Supervises DAG + event bridge
│
├── operator/
│   └── inbox.ex                   # Agent inbox file writer (A3)
│
├── plugin.ex                      # Plugin system
├── plugin/
│   └── info.ex                    # Plugin info struct
│
├── signals/                       # Reactive backbone domain
│   ├── agent_watchdog.ex          # Signal-driven agent watchdog
│   ├── agent_watchdog/
│   │   ├── escalation_engine.ex   # Escalation policy engine
│   │   └── pane_scanner.ex        # Tmux pane output scanner
│   ├── behaviour.ex               # Signal behaviour definition
│   ├── buffer.ex                  # Signal ring buffer
│   ├── bus.ex                     # Single message delivery authority
│   ├── catalog.ex                 # Declarative signal catalog
│   ├── entropy_tracker.ex         # Loop/entropy monitoring
│   ├── event.ex                   # Signal emit/query actions
│   ├── event_payload.ex           # Event payload struct
│   ├── event_stream.ex            # Canonical event buffer + liveness
│   ├── event_stream/
│   │   ├── agent_lifecycle.ex     # Signal emission helper (no Infrastructure imports)
│   │   └── normalizer.ex          # Hook event normalizer
│   ├── from_ash.ex                # Ash notifier -> signal emission
│   ├── hitl_intervention_event.ex # Durable HITL audit record (moved from Infrastructure)
│   ├── message.ex                 # Signal message struct
│   ├── noop.ex                    # No-op signal handler
│   ├── operations.ex              # Ash action surface for messaging/signals
│   ├── preparations/
│   │   ├── event_buffer_reader.ex # Event buffer reader preparation
│   │   ├── load_task_projections.ex # Task projection loader
│   │   └── load_tool_failures.ex  # Tool failure loader
│   ├── protocol_tracker.ex        # Debug trace correlation
│   ├── runtime.ex                 # Signal transport + PubSub broadcast
│   ├── schema_interceptor.ex      # Schema interception
│   ├── task_projection.ex         # Live task projection from event stream
│   ├── tool_failure.ex            # Live tool-failure projection
│   └── topics.ex                  # PubSub topic definitions
│
└── workshop/                      # Agent + team design domain
    ├── active_team.ex             # Runtime/read action surface for active teams
    ├── agent.ex                   # Runtime/read action surface for agents
    ├── agent_entry.ex             # Agent entry struct
    ├── agent_lookup.ex            # Agent lookup utility
    ├── agent_memory.ex            # Workshop memory action surface
    ├── agent_slot.ex              # Agent slot resource
    ├── agent_type.ex              # Reusable agent archetype
    ├── analysis/
    │   ├── agent_health.ex        # Agent health analysis
    │   ├── queries.ex             # Fleet/team query helpers
    │   └── session_eviction.ex    # Session eviction logic
    ├── canvas_state.ex            # Workshop editor state transitions
    ├── comm_rule.ex               # Communication rule resource
    ├── pipeline_prompts.ex        # Pipeline team prompt templates
    ├── preparations/
    │   ├── load_agents.ex         # Agent loader preparation
    │   └── load_teams.ex          # Team loader preparation
    ├── presets.ex                  # Workshop presets
    ├── prompt_protocol.ex         # Shared prompt building behaviour (AD-6)
    ├── spawn.ex                   # Workshop spawn (signal-driven)
    ├── spawn_link.ex              # Spawn link resource
    ├── team.ex                    # Durable authored team definition
    ├── team_member.ex             # Durable team member definition
    ├── team_prompts.ex            # MES team prompt templates
    ├── team_spawn_handler.ex      # Signal-driven team spawn listener
    ├── team_spec.ex               # TeamSpec builder with prompt_module injection (AD-6)
    ├── team_sync.ex               # Team sync utilities
    └── types/
        └── health_status.ex       # Health status Ash type
```
