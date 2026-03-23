# Overlapping / Competing Concepts

### 1. Four independent processors on `:events` (`:new_event`)
- `AgentWatchdog` -- health/escalation
- `EntropyTracker` -- loop detection
- `ProtocolTracker` -- message tracing
- `Mesh.EventBridge` -- DAG/topology

All subscribe to `:events`, all react to `:new_event`. Four GenServers doing independent work on the same stream.

### 2. Five subscribers to `:fleet`
- `AgentWatchdog`
- `TeamSpawnHandler`
- `SessionLifecycle`
- `TeamWatchdog`
- `EventStream`

### 3. Raw PubSub bypasses (outside Signals layer)
- `DashboardMessagingHandlers` -- `Phoenix.PubSub.subscribe("agent:#{session_id}")` directly
- `DashboardSessionControlHandlers` -- raw PubSub subscribe
- `PluginScaffold` -- `Phoenix.PubSub.subscribe("plugin:#{app_name}")`
- `Buffer` -- `Phoenix.PubSub.broadcast("signals:feed")` directly

Topic strings not enforced by `Topics`, not validated by `Catalog`.

### 4. Four all-category subscribers
- `SignalManager` -- attention queue
- `MemoriesBridge` -- episodic memory
- `Buffer` -- UI feed
- `DashboardLive` -- UI updates

### 5. `:decision_log` has three emitters
- `GatewayController` -- HTTP ingestion
- `Mesh.EventBridge` -- event stream transformation
- `HITL.Events` -- HITL intervention

Consumers cannot distinguish source.

### 6. `:fleet_changed` has three emitters
- `TmuxDiscovery` -- session scan
- `AgentProcess` -- per-agent event
- `Signals.Bus` -- message delivery side effect

### 7. Modules in signals/ that don't belong to signals
- `AgentWatchdog` -- agent health monitoring (Infrastructure concern)
- `PaneScanner` -- tmux I/O (Infrastructure concern)
- `EscalationEngine` -- nudge logic (Archon concern)
- `EntropyTracker` -- loop detection (Archon/monitoring concern)
- `ProtocolTracker` -- message tracing (Infrastructure concern)
- `SchemaInterceptor` -- validation gate (Mesh concern)
- `Bus` -- message delivery (Infrastructure concern)
- `HITLInterventionEvent` -- HITL audit log (Infrastructure/HITL concern)

### 8. EventBufferReader broken default
- Defaults to `Ichor.EventBuffer` (doesn't exist)
- Should point to `Ichor.Signals.EventStream`
- Starves `TaskProjection.current/0` and `ToolFailure.recent/0`
