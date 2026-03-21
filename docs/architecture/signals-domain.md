# Signals Domain
Related: [Index](INDEX.md) | [Decisions](decisions.md) | [Infrastructure](infrastructure.md) | [Diagrams](../diagrams/architecture.md)

Signals owns: signal emit/broadcast surface, message delivery (Bus), event store, signal catalog.
Signals does NOT own: fleet health monitoring (AgentWatchdog -- fleet concern), fleet mutations (should emit signal, let Infrastructure react).

---

## What Signals Actually Is

Signals is the nervous system. Everything that happens in the app becomes a signal. Anything that needs to react subscribes. No direct cross-domain calls needed.

The rule: producers emit, subscribers react. A producer never knows who's listening. A subscriber never calls the producer. Signals is the only coupling point between domains.

**But**: signals are NOT a universal replacement for direct calls. Signals cross domain boundaries. Direct calls stay within a subsystem. Overusing signals creates event soup. (AD-2)

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

**Key function**: `Signals.emit(topic, signal)` -- the single entrypoint for all signal emission. Ensures signals go through the catalog, get sequenced, and get broadcast.

**EventBridge bug (P2-2.3 from audit)**: `Signals.EventBridge` calls `Phoenix.PubSub.subscribe/unsubscribe` directly, bypassing `Ichor.Signals`. Should use `Signals.subscribe/unsubscribe`.

### Signals.Catalog

Declarative signal catalog. Lists all valid signal topics, their payload shapes, and descriptions. Source of truth for the signal topology.

Used by `Ichor.Discovery` (planned) to expose signals as observable events in the workflow builder.

### Signals.Buffer -> DELETE (after fix)

Ring buffer for Dashboard replay. Current implementation uses a GenServer to increment a monotonic counter -- this serializes unnecessarily.

**Fix (P3 from audit)**: Replace counter with `:atomics`. Keep GenServer for subscription management only. Or absorb entirely into `Events.Runtime`.

### Signals.FromAsh

Ash notifier -> signal emission. Fires after Ash action commits to translate resource changes into signals.

Per AD-8: Ash notifiers are the correct place to insert Oban jobs for mandatory reactions (not PubSub subscribers). `FromAsh` handles both: emit the observational signal AND insert the Oban job if mandatory work must follow.

### Signals.AgentWatchdog -> Fleet.Runtime (move pending)

**Wrong home** (W1 from audit): AgentWatchdog monitors fleet health. It subscribes to signals, but its purpose is fleet monitoring -- it belongs near the fleet, not in the Signals namespace.

**Current behavior**:
- Beats every 5s
- Detects sessions stale > 120s -> checks AgentProcess + tmux window liveness
- On crash: reassigns tasks on Board, emits `:agent_crashed`, writes inbox notification
- Escalation: nudge warning -> Bus message -> HITLRelay.pause -> zombie alert

**Current violations (P2 from audit)**:
- 2.1: calls `Infrastructure.HITLRelay.pause/unpause` directly (should emit signal)
- 2.2: calls `Factory.Board.list_tasks + update_task` directly (should subscribe to `:agent_crashed`)

**Target**: Move to `Fleet.Runtime`. Emit signals for decisions. Infrastructure subscriber handles HITLRelay. Factory subscriber handles task reassignment.

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
            +--> Mesh.EventBridge (topology -- loss ok)
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
| `:new_event` | EventStream | AgentWatchdog, Dashboard, EventBridge | No |
| `:session_discovered` | EventStream (after fix) | Infrastructure (create AgentProcess) | Yes -> Oban |
| `:agent_crashed` | AgentWatchdog | Factory (reassign tasks), Operator.Inbox | Yes -> Oban |
| `:team_spawn_requested` | Workshop.Spawn | TeamSpawnHandler | Yes -> direct |
| `:team_spawned` | TeamSpawnHandler | Dashboard, Mesh | No |
| `:run_complete` | Projects.RunManager | TeamWatchdog -> cleanup | Yes -> Oban |
| `:run_cleanup_needed` | TeamWatchdog | Factory, Infrastructure, Operator.Inbox | Yes -> Oban |
| `:pipeline_task_claimed` | PipelineTask notifier | Dashboard, EventBridge | No |
| `:message_delivered` | Bus | Dashboard | No |
| `:fleet_changed` | AgentProcess, Bus | Dashboard | No |
| `:heartbeat` | AgentWatchdog | Dashboard liveness indicators | No |

---

## Cross-Domain Violations to Fix

### X1: EventStream fleet mutations (medium priority)

**Current**: `EventStream.ingest_event` calls `AgentProcess/FleetSupervisor` to auto-register agents.

**Fix**: `EventStream` emits `:session_discovered`. Infrastructure subscriber creates `AgentProcess`. One-way dependency: Infrastructure subscribes to Signals, never the reverse.

### X2: AgentWatchdog direct cross-domain calls (medium priority)

**Current**: AgentWatchdog calls `Factory.Board.update_task` and `Infrastructure.HITLRelay.pause` directly.

**Fix**: Emit `:agent_crashed` (already done). Add Factory subscriber that reacts to `:agent_crashed` and reassigns tasks. Add Infrastructure subscriber that reacts to `:escalation_level_2` and calls HITLRelay.pause.

### X3: EventBridge raw PubSub calls (small, Wave 1)

**Current**: `event_bridge.ex:77,289` calls `Phoenix.PubSub.subscribe/unsubscribe` directly.

**Fix**: Use `Ichor.Signals.subscribe/unsubscribe` instead. One-line change per callsite.

---

## Planned: AgentWatchdog Move

AgentWatchdog lives in `Signals.AgentWatchdog` because "it's driven by signals." But its purpose -- fleet health monitoring -- belongs to the fleet. The signals subscription is an implementation detail.

**Target location**: `Fleet.Runtime` namespace (or a dedicated `Fleet.HealthMonitor`).

**Migration path**: Move the module to `lib/ichor/fleet/health_monitor.ex`. Update the supervisor. Keep subscription topics unchanged.
