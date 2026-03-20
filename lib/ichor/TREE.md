 # lib/ichor/ Module Tree

127 files. Annotations derived from @moduledoc (max 10 words each).

```
lib/ichor/
├── application.ex                 # OTP application entry point
├── agent_watchdog.ex              # Consolidated agent health monitor, single GenServer
├── control.ex                     # Ash Domain: agent control plane
├── event_buffer.ex                # Compatibility shim, delegates to Events.Runtime
├── memories_bridge.ex             # Bridges signal stream into Memories knowledge graph
├── memory_store.ex                # Letta-compatible three-tier agent memory GenServer
├── notes.ex                       # ETS-backed storage for event annotations
├── observation_supervisor.ex      # Supervises causal DAG and event bridge
├── observability.ex               # Ash Domain: everything that happened
├── projects.ex                    # Ash Domain: project lifecycle through execution
├── protocol_tracker.ex            # Correlates cross-protocol messages into traces
├── quality_gate.ex                # Enforces quality gates on agent task completion
├── repo.ex                        # Ecto repository for Ichor SQLite database
├── system_supervisor.ex           # Supervises all independent system services
├── tools.ex                       # Ash Domain: MCP tool surfaces for agents
│
├── architecture/
│   └── boundary_audit.ex          # Post-umbrella boundary cleanliness audit
│
├── archon/
│   ├── chat.ex                    # Archon conversation engine, LLM-backed
│   ├── command_manifest.ex        # Archon command metadata source of truth
│   ├── memories_client.ex         # HTTP client for Memories knowledge graph API
│   ├── signal_manager.ex          # Signal-fed managerial state for Archon
│   └── team_watchdog.ex           # Signal-driven team lifecycle monitor
│
├── control/
│   ├── agent.ex                   # Agent Ash resource (Simple data layer)
│   ├── agent_process.ex           # Living agent GenServer, BEAM mailbox delivery
│   ├── agent_type.ex              # Reusable agent archetype with defaults
│   ├── blueprint.ex               # Saved team blueprint (SQLite)
│   ├── blueprint_state.ex         # Pure state transitions for Workshop canvas
│   ├── fleet_supervisor.ex        # DynamicSupervisor for teams and agents
│   ├── host_registry.ex           # Tracks available BEAM nodes
│   ├── presets.ex                 # Workshop blueprint presets and spawn ordering
│   ├── team.ex                    # Team Ash resource (Simple data layer)
│   ├── team_spec_builder.ex       # Builds TeamSpec from Workshop state
│   ├── team_supervisor.ex         # DynamicSupervisor per team
│   ├── tmux_helpers.ex            # Shared tmux spawning helpers
│   ├── analysis/
│   │   ├── agent_health.ex        # Pure failure-rate and loop detection
│   │   ├── queries.ex             # Pure fleet data query functions
│   │   └── session_eviction.ex    # Stale session eviction
│   ├── lifecycle/
│   │   ├── agent_launch.ex        # Launches individual agents
│   │   ├── agent_spec.ex          # Agent runtime spec struct
│   │   ├── cleanup.ex             # Agent/team/tmux cleanup ops
│   │   ├── registration.ex        # Process registration for agents/teams
│   │   ├── team_launch.ex         # Launches and tears down teams
│   │   ├── team_spec.ex           # Team runtime spec struct
│   │   ├── tmux_launcher.ex       # Tmux session/window lifecycle
│   │   └── tmux_script.ex         # Prompt and script file writer
│   ├── types/
│   │   └── health_status.ex       # Ash enum for health status
│   └── views/preparations/
│       ├── load_agents.ex         # Loads agents from runtime registry
│       └── load_teams.ex          # Loads teams from registry and events
│
├── events/
│   ├── event.ex                   # In-memory event struct
│   └── runtime.ex                 # Canonical event buffer + heartbeat + liveness
│
├── gateway/
│   ├── channel.ex                 # Channel adapter behaviour
│   ├── cron_job.ex                # Cron job Ash resource (SQLite)
│   ├── cron_scheduler.ex          # Scheduled job firing GenServer
│   ├── entropy_tracker.ex         # Per-session loop detection
│   ├── event_bridge.ex            # Events to gateway messages bridge
│   ├── hitl_intervention_event.ex # HITL intervention Ash resource (SQLite)
│   ├── hitl_relay.ex              # HITL pause/unpause GenServer
│   ├── output_capture.ex          # Tmux pane output poller
│   ├── schema_interceptor.ex     # Inbound message validation gate
│   ├── tmux_discovery.ex          # Tmux session discovery and agent sync
│   ├── webhook_delivery.ex        # Webhook delivery Ash resource (SQLite)
│   ├── webhook_router.ex          # Durable webhook delivery with backoff
│   ├── agent_registry/
│   │   └── agent_entry.ex         # Agent map constructor and helpers
│   └── channels/
│       ├── ansi_utils.ex          # ANSI escape sequence utilities
│       ├── mailbox_adapter.ex     # BEAM mailbox delivery adapter
│       ├── ssh_tmux.ex            # SSH tmux delivery adapter
│       ├── tmux.ex                # Tmux paste-buffer delivery adapter
│       └── webhook_adapter.ex     # Webhook HTTP delivery adapter
│
├── mesh/
│   ├── causal_dag.ex              # Per-session causal event DAG (ETS)
│   ├── decision_log.ex            # Agent message envelope (Ash embedded)
│   └── decision_log/
│       └── helpers.ex             # DecisionLog pure helpers
│
├── memory_store/
│   ├── persistence.ex             # Disk persistence for memory store
│   └── storage.ex                 # ETS-level memory store operations
│
├── messages/
│   └── bus.ex                     # Single delivery authority for messaging
│
├── observability/
│   ├── error.ex                   # Tool error Ash resource (Simple)
│   ├── event.ex                   # Event Ash resource (SQLite)
│   ├── janitor.ex                 # Periodic event purge GenServer
│   ├── message.ex                 # Message Ash resource (Simple)
│   ├── session.ex                 # Session Ash resource (SQLite)
│   ├── task.ex                    # Task Ash resource (Simple)
│   └── preparations/
│       ├── event_buffer_reader.ex # EventBuffer read shim
│       ├── load_errors.ex         # Error preparation from hook events
│       ├── load_messages.ex       # Message preparation from hook events
│       └── load_tasks.ex          # Task preparation from hook events
│
├── plugs/
│   └── operator_auth.ex           # Operator auth header plug
│
├── projects/
│   ├── artifact.ex                # Unified Genesis artifact (SQLite)
│   ├── completion_handler.ex      # DAG completion → subsystem hot-load
│   ├── dag_generator.ex           # RoadmapItem hierarchy → tasks.jsonl
│   ├── pipeline_prompts.ex        # Pipeline team prompt templates
│   ├── date_utils.ex              # ISO 8601 timestamp parsing
│   ├── graph.ex                   # Pure DAG computation
│   ├── janitor.ex                 # Runner monitor + orphan cleanup
│   ├── lifecycle_supervisor.ex    # MES subsystem supervisor
│   ├── mode_prompts.ex            # Genesis mode prompt templates
│   ├── node.ex                    # Genesis Node Ash resource (SQLite)
│   ├── pipeline_stage.ex          # Pipeline stage derivation
│   ├── project.ex                 # MES project brief (SQLite)
│   ├── project_ingestor.ex        # MES payload → Ash resource
│   ├── research_context.ex        # Dynamic research context for prompts
│   ├── research_ingestor.ex       # Brief → Memories graph ingestion
│   ├── research_store.ex          # Read-only Memories graph interface
│   ├── roadmap_item.ex            # Unified roadmap item (SQLite)
│   ├── run.ex                     # DAG execution session (SQLite)
│   ├── runner.ex                  # Unified run lifecycle GenServer
│   ├── runtime.ex                 # DAG pipeline runtime GenServer
│   ├── scheduler.ex               # MES run spawner (60s tick)
│   ├── spawn.ex                   # Team spawner for DAG + Genesis
│   ├── subsystem_loader.ex        # Hot-loads BEAM modules
│   ├── subsystem_scaffold.ex      # Creates Mix project dirs
│   ├── team_prompts.ex            # MES team prompt templates
│   ├── team_spec.ex               # TeamSpec builder across run modes
│   ├── job.ex                     # DAG execution unit (SQLite)
│   ├── job/changes/
│   │   └── sync_run_process.ex    # Notifies RunProcess on job transition
│   ├── job/preparations/
│   │   └── filter_available.ex    # Filters unblocked jobs
│   └── types/
│       └── work_status.ex         # Ash enum for work lifecycle
│
├── signals/
│   ├── buffer.ex                  # Signal ring buffer (200 events)
│   ├── catalog.ex                 # Declarative signal catalog
│   ├── event.ex                   # Signal operations Ash resource
│   ├── from_ash.ex                # Ash notifier → signal emission
│   └── runtime.ex                 # Signal transport + PubSub broadcast
│
├── tasks/
│   ├── board.ex                   # Team board task actions + signals
│   └── jsonl_store.ex             # In-place tasks.jsonl mutations
│
└── tools/
    ├── agent_memory.ex            # Agent memory MCP tools
    ├── genesis.ex                 # Genesis pipeline MCP tools
    ├── profiles.ex                # Tool exposure profiles
    ├── project_execution.ex       # Project/DAG execution MCP tools
    ├── runtime_ops.ex             # Fleet/messaging/diagnostics MCP tools
    └── archon/
        └── memory.ex              # Archon knowledge graph MCP tools
```
