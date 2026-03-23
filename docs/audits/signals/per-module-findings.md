# Per-Module Audit Findings

### AgentWatchdog (458 lines, GenServer, signals/)
- **Misplaced**: Does Factory.Board task reassignment and Operator.Inbox writes directly on crash. Should emit signal only; subscribers react.
- **`AgentProcess.list_all/0` called twice per 5s tick** (escalation + pane scan)
- **`HITLRelay.pause/4` synchronous in tick** -- can block the beat if HITLRelay is slow
- `EscalationEngine.clear/2` dead code (parent uses `Map.pop` inline)
- Duplicate `session_id/1` between watchdog and EscalationEngine
- Cross-domain deps: Factory.Board, Infrastructure.AgentProcess/HITLRelay/Tmux, Operator.Inbox, Workshop.AgentEntry

### EntropyTracker (190 lines, GenServer, signals/)
- **Every public function except `start_link` has zero callers** -- fully autonomous via `handle_info`
- **Tuple shape bug**: `handle_info` inserts 2-tuples `{tool, type}`, `record_and_score` expects 3-tuples. Same window. MapSet uniqueness becomes meaningless with mixed arities.
- `register_agent/2` -- zero callers, vestigial
- `get_window/1`, `reset/0` -- zero callers, documented as "for testing" but no tests call them

### ProtocolTracker (174 lines, GenServer, signals/)
- **Moduledoc overstates capability** -- claims multi-hop correlation, only traces 3 event types
- `compute_stats/0` hardcodes `total_unread: 0`, `total_pending: 0`
- `TraceEvent` struct completely orphaned -- never constructed anywhere
- `state.trace_count` write-only (incremented, never read)
- Only callers: `debug_controller.ex`

### EventStream (427 lines, GenServer, signals/)
- **3 concerns in one GenServer**: event buffer (ETS), heartbeat liveness (state), tool interception (channel dispatch)
- `publish_fact/2` -- dead code, wrong emit shape (`%{name, attrs}` vs `%{event: event}`)
- `latest_session_state/1` -- dead code, zero callers
- `handle_cast({:expire_tombstone})` -- dead code, never dispatched
- **ETS leaks**: `@aliases` grows unbounded (never cleaned). `@tools` leaks on abandoned tool calls.
- Double tombstone check per ingest (minor)

### Bus (195 lines, pure module, signals/)
- **Emits `:fleet_changed` with empty payload** -- catalog expects `keys: [:agent_id]`
- **Emits `:fleet_changed` on every message delivery** -- semantically wrong (signal means "registry changed", not "message sent"). All 5 `:fleet` subscribers receive noise.
- `resolve/1` public but only called internally
- `start_message_log/0` called outside supervision tree (ETS owned by Application process)

### Buffer (58 lines, GenServer, signals/)
- Clean. No dead code. All functions have callers.
- ETS table `:public` but only GenServer writes -- should be `:protected` per SF-7
- Re-broadcasts on `"signals:feed"` bypassing Signals layer (raw PubSub)

### EventBufferReader (20 lines, pure, signals/preparations/)
- **BUG**: defaults to `Ichor.EventBuffer` which doesn't exist
- Fix: change default to `Ichor.Signals.EventStream`
- `LoadToolFailures` and `LoadTaskProjections` silently return `[]`

### EventBridge (308 lines, GenServer, mesh/)
- Correctly placed in Mesh domain
- Silently swallows CausalDAG process crashes (`catch :exit, _ -> state`)
- `confidence_score`/`entropy_score` always 0.0 in DAG nodes (fields exist but never populated)
- Intent mapping (20 clauses) may outgrow this file

### SchemaInterceptor (55 lines, pure, signals/)
- **Misplaced**: belongs in Mesh (alongside DecisionLog) or inline in controller
- **Validates nothing** -- just wraps `DecisionLog.Helpers.from_json/1`
- `build_violation_event/3` -- dead code, zero callers

### TeamWatchdog (112 lines, GenServer, archon/)
- Correctly placed in Archon domain
- **3 unused subscriptions**: `:pipeline`, `:planning`, `:monitoring` -- all handled signals are `:fleet`
- `completed_runs` MapSet grows unbounded (memory leak on long-running nodes)
- Session completion check uses fragile `String.contains?` substring matching
