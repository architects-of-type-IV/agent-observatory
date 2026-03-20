 # lib/ichor/ Module Tree

Current high-level shape after the domain cleanup. This is intentionally
condensed and only lists the active ownership boundaries and notable modules.

```
lib/ichor/
├── application.ex                 # OTP application entry point
├── memories_bridge.ex             # Bridges signal stream into Memories knowledge graph
├── memory_store.ex                # Letta-compatible three-tier agent memory GenServer
├── notes.ex                       # ETS-backed storage for event annotations
├── repo.ex                        # Ecto repository for Ichor SQLite database
├── runtime_supervisor.ex          # Shared runtime services supervisor
│
├── archon/
│   ├── chat.ex                    # Archon conversation engine, LLM-backed
│   ├── command_manifest.ex        # Archon command metadata source of truth
│   ├── manager.ex                 # Ash action surface for Archon control
│   ├── memory.ex                  # Ash resource for Archon memory access
│   ├── memories_client.ex         # HTTP client for Memories knowledge graph API
│   ├── signal_manager.ex          # Signal-fed managerial state for Archon
│   └── team_watchdog.ex           # Signal-driven team lifecycle monitor
│
├── memory_store/
│   ├── persistence.ex             # Disk persistence for memory store
│   └── storage.ex                 # ETS-level memory store operations
│
├── mesh/
│   ├── causal_dag.ex              # Per-session causal topology DAG
│   ├── decision_log.ex            # Causal message envelope (embedded)
│   ├── decision_log/
│   │   └── helpers.ex             # DecisionLog pure helpers
│   └── supervisor.ex              # Supervises DAG + event bridge
│
├── factory/
│   ├── artifact.ex                # Embedded SDLC artifact
│   ├── project.ex                 # Durable MES project resource
│   ├── roadmap_item.ex            # Embedded planning tree item
│   ├── pipeline.ex                # Pipeline resource
│   ├── pipeline_task.ex           # Executable pipeline task resource
│   ├── floor.ex                   # Factory operator/control actions
│   ├── spawn.ex                   # Planning/pipeline team launch orchestration
│   ├── runner.ex                  # MES/pipeline run lifecycle GenServer
│   ├── project_stage.ex           # Project stage derivation
│   ├── pipeline_graph.ex          # Pure pipeline graph functions
│   ├── pipeline_compiler.ex       # Roadmap -> pipeline compilation
│   ├── pipeline_monitor.ex        # Pipeline runtime monitor
│   ├── mes_scheduler.ex           # MES run scheduler
│   ├── planning_prompts.ex        # Planning team prompt templates
│   ├── plugin_loader.ex           # Loads generated plugins
│   ├── plugin_scaffold.ex         # Creates plugin project dirs
│   └── workers/                   # Oban maintenance workers
│
├── infrastructure/
│   ├── operations.ex              # Ash action surface for infrastructure
│   ├── cron_job.ex                # Durable cron job resource
│   ├── webhook_delivery.ex        # Durable webhook delivery resource
│   ├── hitl_intervention_event.ex # Durable HITL audit record
│   ├── hitl_relay.ex              # HITL pause/unpause relay
│   ├── agent_process.ex           # BEAM mailbox-backed agent process
│   ├── agent_launch.ex            # Full agent launcher
│   ├── team_launch.ex             # Team launch/teardown runtime
│   ├── agent_spec.ex              # Generic runtime agent spec
│   ├── team_spec.ex               # Generic runtime team spec
│   ├── cleanup.ex                 # Runtime cleanup operations
│   ├── registration.ex            # Agent/team registration helpers
│   ├── tmux.ex                    # Tmux delivery/runtime adapter
│   ├── tmux_discovery.ex          # Tmux session discovery
│   ├── output_capture.ex          # Pane output poller
│   ├── webhook_router.ex          # Durable webhook transport
│   ├── cron_scheduler.ex          # Cron execution runtime
│   └── plugs/operator_auth.ex     # Operator auth header plug
│
├── signals/
│   ├── operations.ex              # Ash action surface for messaging/signals
│   ├── event.ex                   # Signal emit/query actions
│   ├── task_projection.ex         # Live task projection from event stream
│   ├── tool_failure.ex            # Live tool-failure projection
│   ├── bus.ex                     # Single message delivery authority
│   ├── runtime.ex                 # Signal transport + PubSub broadcast
│   ├── event_stream.ex            # Canonical event buffer + liveness
│   ├── event_bridge.ex            # Event -> mesh topology bridge
│   ├── agent_watchdog.ex          # Signal-driven agent watchdog
│   ├── protocol_tracker.ex        # Debug trace correlation
│   ├── entropy_tracker.ex         # Loop/entropy monitoring
│   ├── catalog.ex                 # Declarative signal catalog
│   ├── buffer.ex                  # Signal ring buffer
│   ├── from_ash.ex                # Ash notifier -> signal emission
│   └── preparations/              # Event-stream query projections
│
└── workshop/
    ├── team.ex                    # Durable authored team definition
    ├── team_member.ex             # Durable team member definition
    ├── agent_type.ex              # Reusable agent archetype
    ├── agent.ex                   # Runtime/read action surface for agents
    ├── active_team.ex             # Runtime/read action surface for active teams
    ├── agent_memory.ex            # Workshop memory action surface
    ├── canvas_state.ex            # Workshop editor state transitions
    ├── team_spec.ex               # TeamSpec builder across current run modes
    ├── team_prompts.ex            # MES team prompt templates
    ├── pipeline_prompts.ex        # Pipeline team prompt templates
    ├── presets.ex                 # Workshop presets
    ├── team_spawn_handler.ex      # Signal-driven team spawn listener
    └── analysis/                  # Fleet/team query helpers
```
