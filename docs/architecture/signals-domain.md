# Signals Domain
Related: [Index](INDEX.md) | [Decisions](decisions.md) | [Infrastructure](infrastructure.md) | [Diagrams](../diagrams/architecture.md)

Signals owns: signal emit/broadcast surface, message delivery (Bus), event store, signal catalog, GenStage pipeline, signal accumulator processes.
Signals does NOT own: fleet health monitoring (AgentWatchdog -- fleet concern), fleet mutations (should emit signal, let Infrastructure react).

---

## What Signals Actually Is

Signals is the nervous system. Everything that happens in the app becomes a signal. Anything that needs to react subscribes. No direct cross-domain calls needed.

The rule: producers emit, subscribers react. A producer never knows who's listening. A subscriber never calls the producer. Signals is the only coupling point between domains.

**But**: signals are NOT a universal replacement for direct calls. Signals cross domain boundaries. Direct calls stay within a subsystem. Overusing signals creates event soup. (AD-2)

---

## GenStage Pipeline (ADR-026)

The signal system now runs two parallel paths:

```
Domain event
  ├─> Signals.emit -> Phoenix.PubSub broadcast (fire-and-forget, observational)
  │
  └─> Events.Ingress (GenStage producer)
        -> Signals.Router (GenStage consumer, topic-based routing)
           -> Signals.SignalProcess (per {module, key} accumulator GenServer)
              -> Signals.ActionHandler (dispatch to real system actions)
```

**GenStage pipeline components:**

| Module | Role |
|--------|------|
| `Events.Ingress` | GenStage producer. Buffers events pushed via `Ingress.push/1`. Also persists to `StoredEvent` (async, excludes `:signal_bridge` source). |
| `Signals.Router` | GenStage consumer. Builds a routing table from registered signal modules. Routes each event to matching modules based on topic. |
| `Signals.SignalProcess` | Stateful accumulator GenServer. One per `{signal_module, key}`. Accumulates events, calls `handler` on flush (after `ready?` check). Idle timeout 5 min, flush interval 10s. Started dynamically by Router via `ProcessSupervisor` + `ProcessRegistry`. |
| `Signals.ActionHandler` | Dispatches signal activations to concrete system actions (HITL pause, Bus notification, etc.). |
| `Signals.PipelineSupervisor` | `rest_for_one` supervisor wrapping Ingress + Router. Router restart re-subscribes to a live Ingress. |

**Three signal modules (ADR-026 projectors):**

| Module | Topic | Key | Action |
|--------|-------|-----|--------|
| `Signals.Agent.ToolBudget` | tool_use events | session_id | Fires when tool budget exhausted (HITLRelay removed; action via ActionHandler) |
| `Signals.Agent.MessageProtocol` | message events | session_id | Tracks protocol violations |
| `Signals.Agent.Entropy` | tool_use/message events | session_id | Detects repetitive loops |

**`Signals.Behaviour`** -- the callback contract all signal modules implement: `signal_name/0`, `topics/0`, `key_for_event/1`, `accumulate/2`, `ready?/1`, `flush/1`.

**Durable storage:**
- `Events.StoredEvent` -- Ash resource (PostgreSQL, table `stored_events`). Append-only event log populated by Ingress.
- `Signals.Checkpoint` -- Ash resource (PostgreSQL, table `signal_checkpoints`). Identity `{signal_module, key}`. Tracks last processed position per projector for crash recovery.

---

## Core Modules

### Signals.EventStream -> Events.Runtime (rename pending)

ETS-backed event store + normalizer. Stores raw hook events from Claude agents, emits signals.

**Current name is wrong** (W3 from audit): "Stream" implies subscription, but this is a store. Rename to `Events.Runtime` or conceptually `EventStore`.

**Key responsibilities**:
- Receive raw hook events from `POST /api/events`
- Normalize into `%Event{}` structs
- Insert into ETS ring buffer (`:ichor_events`)
- Update session activity timestamps (`:ichor_sessions`)
- Emit `:new_event` signal for subscribers

**Current boundary violation (X1)**: EventStream calls `AgentProcess/FleetSupervisor` directly to auto-register agents when events arrive. This couples the event store to the fleet.

**Target fix (W2-3)**: EventStream emits `:session_discovered` signal. An Infrastructure subscriber (or Oban job) reacts by spawning AgentProcess. EventStream stays a store + broadcaster.

### Signals.Bus -> Transport.MessageBus (rename pending)

Single message delivery authority. Routes directed agent-to-agent and operator-to-agent messages.

**Different from PubSub signals**: Bus delivers to a specific target. PubSub broadcasts to all subscribers. These are fundamentally different systems with different reliability models.

**Target resolution**:
- `"team:name"` -> TeamSupervisor.member_ids -> send to each member
- `"fleet:all"` -> AgentProcess.list_all -> broadcast
- `"role:worker"` -> filter by role metadata -> send to matching agents
- bare ID -> single agent delivery

**Delivery fallback chain**:
1. AgentProcess alive? -> `AgentProcess.send_message`
2. Process dead, tmux alive? -> `Tmux.deliver(target, msg)`
3. Neither alive -> log warning, `delivered: 0`

**After delivery**: logs to ETS, emits `:message_delivered` signal.

### Signals.Runtime

Signal transport + PubSub broadcast layer. Wraps `Phoenix.PubSub` with typed signal emission.

**Key function**: `Signals.emit(topic, signal)` -- the single entrypoint for all signal emission. Ensures signals go through the catalog, get sequenced, and get broadcast. Signals also calls `Events.Ingress.push/1` to feed the GenStage pipeline.

**Deleted indirection layer**: `Signals.Behaviour`, `Signals.Noop`, `Signals.Event`, and the `impl()` dispatch pattern were removed in the ADR-026 refactoring. Signal module abstraction now uses the `Signals.Behaviour` callback contract (see GenStage Pipeline section above).

**EventBridge (removed)**: `Signals.EventBridge` and `Mesh.*` (CausalDAG, DecisionLog, Mesh.Supervisor) were deleted in commit f20ac4b. The topology/DAG pipeline no longer exists.

### Signals.Catalog

Declarative signal catalog. Lists all valid signal topics, their payload shapes, and descriptions. Source of truth for the signal topology.

Used by `Ichor.Discovery` (planned) to expose signals as observable events in the workflow builder.

### Signals.Buffer (now `Projector.SignalBuffer`)

Ring buffer for Dashboard replay. Moved from `Signals.Buffer` to `Projector.SignalBuffer` during the projector extraction refactoring. Lives under `RuntimeSupervisor` (not LifecycleSupervisor).

### Signals.FromAsh

Ash notifier -> signal emission. Fires after Ash action commits to translate resource changes into signals.

Per AD-8: Ash notifiers are the correct place to insert Oban jobs for mandatory reactions (not PubSub subscribers). `FromAsh` handles both: emit the observational signal AND insert the Oban job if mandatory work must follow.

### Projector.AgentWatchdog (formerly Signals.AgentWatchdog)

Moved from `Signals.AgentWatchdog` to `Projector.AgentWatchdog` during the projector extraction refactoring. Lives under `RuntimeSupervisor` (not LifecycleSupervisor).

**Behavior**:
- Beats every 5s
- Detects sessions stale > 120s -> checks `Fleet.AgentProcess` + tmux window liveness
- On crash: reassigns tasks on Board, emits `:agent_crashed`, writes inbox notification
- Escalation: nudge warning -> Bus message -> zombie alert (HITLRelay removed)

The violations noted in the audit (P2.1, P2.2 -- direct cross-domain calls) are tracked but not yet fully resolved.

---

## Reliability Model (AD-8)

Three layers with different reliability guarantees:

```
Ash (durable truth)
  |
  +--> Ash Notifier: insert Oban job (mandatory reactions)
  |
  +--> Signals.FromAsh: emit PubSub signal (observational fanout)
            |
            +--> Dashboard LiveView (UI update -- loss ok)
            +--> AgentWatchdog (health check -- loss ok)
            +--> Buffer (replay -- loss ok)
```

**Mandatory reactions** (cleanup, task reassignment, escalation, webhook retry) MUST flow through Oban, not PubSub. Inserted directly from Ash notifiers or GenServer action handlers -- not from PubSub subscribers.

**Observational reactions** (UI updates, logs, topology, dashboard refresh) flow through PubSub. Loss is acceptable. These are eventually consistent.

**The volatile hop problem**: if mandatory work is routed `PubSub -> subscriber -> Oban.insert`, and the subscriber is down when the signal fires, the Oban job is never enqueued. That's absent execution, not delayed execution.

---

## Signal Topics (key subset)

| Topic | Producer | Subscribers | Mandatory? |
|-------|----------|-------------|-----------|
| `:new_event` | EventStream | AgentWatchdog, Dashboard | No |
| `:session_discovered` | EventStream (after fix) | Fleet subscriber (create Fleet.AgentProcess) | Yes -> Oban |
| `:agent_crashed` | AgentWatchdog | Factory (reassign tasks), Operator.Inbox | Yes -> Oban |
| `:team_spawn_requested` | Workshop.Spawn | TeamSpawnHandler | Yes -> direct |
| `:team_spawned` | TeamSpawnHandler | Dashboard | No |
| `:run_complete` | Projects.RunManager | TeamWatchdog -> cleanup | Yes -> Oban |
| `:run_cleanup_needed` | TeamWatchdog | Factory, Infrastructure, Operator.Inbox | Yes -> Oban |
| `:pipeline_task_claimed` | PipelineTask notifier | Dashboard | No |
| `:message_delivered` | Bus | Dashboard | No |
| `:fleet_changed` | AgentProcess, Bus | Dashboard | No |
| `:heartbeat` | AgentWatchdog | Dashboard liveness indicators | No |

---

## Cross-Domain Violations to Fix

### X1: EventStream fleet mutations (medium priority)

**Current**: `EventStream.ingest_event` calls `AgentProcess/FleetSupervisor` to auto-register agents.

**Fix**: `EventStream` emits `:session_discovered`. Infrastructure subscriber creates `AgentProcess`. One-way dependency: Infrastructure subscribes to Signals, never the reverse.

### X2: AgentWatchdog direct cross-domain calls (medium priority)

**Current**: AgentWatchdog calls `Factory.Board.update_task` directly on crash detection.

**Fix**: Emit `:agent_crashed` (already done). Add Factory subscriber that reacts to `:agent_crashed` and reassigns tasks via Oban job.

**Note**: `HITLRelay.pause` is no longer part of the escalation chain -- HITL subsystem was deleted. Escalation level 2 now emits a zombie alert signal only.

### X3: EventBridge (resolved -- module deleted)

`Ichor.Gateway.EventBridge`, `Ichor.Mesh.CausalDAG`, `Ichor.Mesh.DecisionLog`, and `Ichor.Mesh.Supervisor` were deleted in commit f20ac4b. The raw PubSub calls no longer exist.

---

## Deleted Subsystems

### Signals indirection layer (deleted)
`Signals.Behaviour` (old impl() dispatch), `Signals.Noop`, `Signals.Event` (Ash resource for signal storage), and `MemoriesBridge` projector were removed. Signal modules now use the `Signals.Behaviour` callback directly.

### Tmux.Ssh adapter (deleted)
Removed from `Infrastructure.Tmux` namespace. Remote tmux via SSH is no longer part of the system.

### DefaultHandler and Benchmark (deleted)
Removed from the signal handling and performance tooling namespaces.
