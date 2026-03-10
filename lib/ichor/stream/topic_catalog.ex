defmodule Ichor.Stream.TopicCatalog do
  @moduledoc """
  Static catalog of all PubSub topics in the ICHOR system.
  Source of truth for the /stream page and Archon Watchdog.
  """

  @type topic_entry :: %{
          topic: String.t(),
          category: atom(),
          messages: [%{shape: String.t(), description: String.t()}],
          broadcasters: [String.t()],
          subscribers: [String.t()]
        }

  # ── Catalog ──────────────────────────────────────────────────────────

  @catalog [
    # ── Events ──────────────────────────────────────────────────────
    %{
      topic: "events:stream",
      category: :events,
      messages: [
        %{shape: "{:new_event, %Event{}}", description: "Every hook event ingested by EventController"}
      ],
      broadcasters: ["EventController"],
      subscribers: ["AgentMonitor", "NudgeEscalator", "QualityGate", "EventBridge", "ProtocolTracker", "SwarmMonitor", "DashboardLive"]
    },

    # ── Heartbeat ───────────────────────────────────────────────────
    %{
      topic: "heartbeat",
      category: :system,
      messages: [
        %{shape: "{:heartbeat, count}", description: "Monotonic counter every 5 seconds"}
      ],
      broadcasters: ["Heartbeat"],
      subscribers: ["NudgeEscalator", "PaneMonitor", "ProtocolTracker", "DashboardLive"]
    },

    # ── Fleet Lifecycle ─────────────────────────────────────────────
    %{
      topic: "fleet:lifecycle",
      category: :fleet,
      messages: [
        %{shape: "{:agent_started, id, %{role, team}}", description: "AgentProcess init"},
        %{shape: "{:agent_paused, id}", description: "AgentProcess paused via HITL"},
        %{shape: "{:agent_resumed, id}", description: "AgentProcess resumed"},
        %{shape: "{:agent_stopped, id, reason}", description: "AgentProcess terminated"},
        %{shape: "{:team_created, name, %{project, strategy}}", description: "New team started"},
        %{shape: "{:team_disbanded, team_name}", description: "Team removed"},
        %{shape: ":hosts_changed", description: "Cluster node joined or departed"}
      ],
      broadcasters: ["AgentProcess", "TeamSupervisor", "FleetSupervisor", "HostRegistry"],
      subscribers: []
    },

    # ── Gateway ─────────────────────────────────────────────────────
    %{
      topic: "gateway:registry",
      category: :gateway,
      messages: [
        %{shape: ":registry_changed", description: "AgentRegistry ETS table modified"}
      ],
      broadcasters: ["AgentRegistry"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "gateway:messages",
      category: :gateway,
      messages: [
        %{shape: "{:decision_log, %DecisionLog{}}", description: "Inter-agent message routed through gateway"}
      ],
      broadcasters: ["GatewayController", "EventBridge", "HITLRelay"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "gateway:violations",
      category: :gateway,
      messages: [
        %{shape: "{:schema_violation, event_map}", description: "Schema validation failure on ingest"}
      ],
      broadcasters: ["GatewayController"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "gateway:topology",
      category: :gateway,
      messages: [
        %{shape: "{:node_state_update, %{agent_id, state, ...}}", description: "Agent node state change in topology"},
        %{shape: "%{session_id, state: \"alert_entropy\"}", description: "Entropy alert from EntropyTracker"},
        %{shape: "%{nodes: [...], edges: [...]}", description: "Full topology snapshot from TopologyBuilder"}
      ],
      broadcasters: ["GatewayController", "EntropyTracker", "TopologyBuilder"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "gateway:entropy_alerts",
      category: :gateway,
      messages: [
        %{shape: "%{event_type: \"entropy_alert\", session_id, entropy_score, repeated_pattern, ...}", description: "Repeated behavior pattern detected"}
      ],
      broadcasters: ["EntropyTracker"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "gateway:capabilities",
      category: :gateway,
      messages: [
        %{shape: "{:capability_update, state_map}", description: "Agent capability map changed"}
      ],
      broadcasters: ["CapabilityMap"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "gateway:dlq",
      category: :gateway,
      messages: [
        %{shape: "{:dead_letter, %WebhookDelivery{}}", description: "Failed webhook delivery sent to dead letter queue"}
      ],
      broadcasters: ["WebhookRouter"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "gateway:audit",
      category: :gateway,
      messages: [
        %{shape: "{:gateway_audit, %{envelope_id, channel, from, recipient_count, ...}}", description: "Message routing audit trail"}
      ],
      broadcasters: ["Gateway.Router"],
      subscribers: []
    },
    %{
      topic: "gateway:mesh_control",
      category: :gateway,
      messages: [
        %{shape: "{:mesh_pause, %{initiated_by, timestamp}}", description: "God-mode mesh pause"}
      ],
      broadcasters: ["DashboardSessionControlHandlers"],
      subscribers: []
    },

    # ── Agent ───────────────────────────────────────────────────────
    %{
      topic: "agent:crashes",
      category: :agent,
      messages: [
        %{shape: "{:agent_crashed, session_id, team_name, reassigned_count}", description: "Agent confirmed dead, tasks reassigned"}
      ],
      broadcasters: ["AgentMonitor"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "agent:nudge",
      category: :agent,
      messages: [
        %{shape: "{:nudge_warning, session_id, agent_name, 0}", description: "Agent stale: warning level"},
        %{shape: "{:nudge_sent, session_id, agent_name, 1}", description: "Nudge message sent via tmux"},
        %{shape: "{:nudge_escalated, session_id, agent_name, 2}", description: "Agent auto-paused via HITL"},
        %{shape: "{:nudge_zombie, session_id, agent_name, 3}", description: "Zombie: agent unresponsive"}
      ],
      broadcasters: ["NudgeEscalator"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "agent:{id}:activity",
      category: :agent,
      dynamic: true,
      messages: [
        %{shape: "{:agent_event, %Event{}}", description: "Per-agent event stream"},
        %{shape: "{:terminal_output, session_id, output}", description: "Captured tmux output"}
      ],
      broadcasters: ["Gateway.Router", "OutputCapture"],
      subscribers: ["DashboardLive (slideout)"]
    },
    %{
      topic: "agent:{id}",
      category: :agent,
      dynamic: true,
      messages: [
        %{shape: "{:new_mailbox_message, message_map}", description: "Direct message to agent mailbox"}
      ],
      broadcasters: ["MailboxAdapter", "Operator"],
      subscribers: ["Channels.subscribe_agent/1"]
    },
    %{
      topic: "agent:{id}:instructions",
      category: :agent,
      dynamic: true,
      messages: [
        %{shape: "{:global_instructions, %{agent_class, instructions}}", description: "Pushed instructions to agent class"}
      ],
      broadcasters: ["DashboardSessionControlHandlers"],
      subscribers: []
    },
    %{
      topic: "agent:{id}:scheduled",
      category: :agent,
      dynamic: true,
      messages: [
        %{shape: "{:scheduled_job, agent_id, payload}", description: "Cron-scheduled job fired for agent"}
      ],
      broadcasters: ["CronScheduler"],
      subscribers: []
    },

    # ── HITL ────────────────────────────────────────────────────────
    %{
      topic: "session:hitl:{id}",
      category: :hitl,
      dynamic: true,
      messages: [
        %{shape: "{:hitl, %GateOpenEvent{...}}", description: "Agent paused, gate opened"},
        %{shape: "{:hitl, %GateCloseEvent{...}}", description: "Agent resumed, buffered messages flushed"}
      ],
      broadcasters: ["HITLRelay"],
      subscribers: ["DashboardLive", "SessionDrilldownLive"]
    },

    # ── DAG / Mesh ──────────────────────────────────────────────────
    %{
      topic: "session:dag:{id}",
      category: :mesh,
      dynamic: true,
      messages: [
        %{shape: "%{event: \"dag_delta\", session_id, added_nodes, updated_nodes, added_edges}", description: "Causal DAG incremental update"}
      ],
      broadcasters: ["CausalDAG"],
      subscribers: ["TopologyBuilder", "DashboardLive"]
    },

    # ── Team ────────────────────────────────────────────────────────
    %{
      topic: "team:{name}",
      category: :team,
      dynamic: true,
      messages: [
        %{shape: "{:task_created, task}", description: "New task added to team"},
        %{shape: "{:task_deleted, task_id}", description: "Task removed from team"},
        %{shape: "{:task_updated, task}", description: "Task status or assignment changed"}
      ],
      broadcasters: ["DashboardTaskHandlers"],
      subscribers: ["Channels.subscribe_team/1"]
    },
    %{
      topic: "teams:update",
      category: :team,
      messages: [
        %{shape: "{:tasks_updated, team_name}", description: "Team task list changed (any CRUD)"}
      ],
      broadcasters: ["DashboardTaskHandlers"],
      subscribers: ["AgentRegistry", "DashboardLive"]
    },

    # ── Monitoring ──────────────────────────────────────────────────
    %{
      topic: "protocols:update",
      category: :monitoring,
      messages: [
        %{shape: "{:protocol_update, stats_map}", description: "Protocol tracker stats recomputed"}
      ],
      broadcasters: ["ProtocolTracker"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "quality:gate",
      category: :monitoring,
      messages: [
        %{shape: "{:gate_passed, session_id, task_id, done_when}", description: "Quality gate verification passed"},
        %{shape: "{:gate_failed, session_id, task_id, done_when, output}", description: "Quality gate verification failed"}
      ],
      broadcasters: ["QualityGate"],
      subscribers: ["DashboardLive"]
    },
    %{
      topic: "pane:signals",
      category: :monitoring,
      messages: [
        %{shape: "{:agent_done, session_id, agent_id, summary}", description: "Agent signalled DONE in tmux output"},
        %{shape: "{:agent_blocked, session_id, agent_id, reason}", description: "Agent signalled BLOCKED in tmux output"}
      ],
      broadcasters: ["PaneMonitor"],
      subscribers: []
    },
    %{
      topic: "swarm:update",
      category: :monitoring,
      messages: [
        %{shape: "{:swarm_state, state_map}", description: "Swarm pipeline state recomputed"}
      ],
      broadcasters: ["SwarmMonitor"],
      subscribers: ["DashboardLive"]
    },

    # ── Messages ────────────────────────────────────────────────────
    %{
      topic: "messages:stream",
      category: :messages,
      messages: [
        %{shape: "{:message_delivered, agent_id, msg_map}", description: "Message delivered to agent via AgentProcess"}
      ],
      broadcasters: ["AgentProcess.Delivery"],
      subscribers: []
    },

    # ── Memory ──────────────────────────────────────────────────────
    %{
      topic: "memory:blocks",
      category: :memory,
      messages: [
        %{shape: "{:block_changed, block_id, label}", description: "Agent memory block modified"}
      ],
      broadcasters: ["MemoryStore"],
      subscribers: []
    },
    %{
      topic: "memory:{agent_name}",
      category: :memory,
      dynamic: true,
      messages: [
        %{shape: "{:memory_changed, agent_name, event}", description: "Per-agent memory change notification"}
      ],
      broadcasters: ["MemoryStore"],
      subscribers: []
    },

    # ── Dashboard ───────────────────────────────────────────────────
    %{
      topic: "dashboard:commands",
      category: :system,
      messages: [
        %{shape: "{:dashboard_command, command}", description: "External command pushed to dashboard"}
      ],
      broadcasters: ["Channels"],
      subscribers: ["Channels.subscribe_dashboard_commands/0"]
    }
  ]

  # ── Public API ────────────────────────────────────────────────────

  @spec all() :: [topic_entry()]
  def all, do: @catalog

  @spec categories() :: [atom()]
  def categories, do: @catalog |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()

  @spec by_category(atom()) :: [topic_entry()]
  def by_category(cat), do: Enum.filter(@catalog, &(&1.category == cat))

  @spec subscribable_topics() :: [String.t()]
  def subscribable_topics do
    @catalog
    |> Enum.reject(&(&1[:dynamic] == true))
    |> Enum.map(& &1.topic)
  end
end
