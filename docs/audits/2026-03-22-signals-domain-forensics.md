# Signals Domain Forensic Audit

**Date**: 2026-03-22
**Scope**: `lib/ichor/signals/` (3243 lines, 20 files + subdirectories)
**Framework**: SPECS/dag/AGENT_PROMPT.md (shape-first, DAG traversal)
**Status**: Waiting for PubSub/Archon research agent. Holistic synthesis pending.

---

## 1. Boundary Audit (DAG Traversal per Module)

### Correctly Placed

| Module | Lines | Classification | Notes |
|--------|-------|---------------|-------|
| `message.ex` | 67 | Pure transformation | Struct builder, no side effects |
| `behaviour.ex` | 12 | Contract | Callback declarations only |
| `catalog.ex` | 735 | Pure transformation | Compile-time registry, all functions pure |
| `topics.ex` | 16 | Pure transformation | String interpolation |
| `runtime.ex` | 104 | Behaviour impl | Owns PubSub transport |
| `noop.ex` | 31 | Behaviour impl | Test no-op |
| `from_ash.ex` | 151 | Notifier adapter | Cross-domain by design |
| `hitl_intervention_event.ex` | 85 | Ash Resource | Persisted audit log |
| `event.ex` | 105 | Action-only Resource | Ash facade for MCP/Archon |
| `event_stream/normalizer.ex` | -- | Pure transformation | Well-extracted, no side effects |
| `agent_watchdog/escalation_engine.ex` | -- | Pure transformation | Decision logic, effects injected via callback |
| `agent_watchdog/pane_scanner.ex` | -- | Mostly pure | Closure-based deferred effects |
| `preparations/*.ex` | -- | Ash preparations | Thin adapters |

### Misplaced (should move out of signals/)

| Module | Lines | Current | Should Be | Reason |
|--------|-------|---------|-----------|--------|
| `agent_watchdog.ex` | 474 | Signals | Infrastructure or Archon | Agent health orchestration; 6 cross-domain imports (Factory.Board, Infrastructure.{AgentProcess,HITLRelay,Tmux}, Operator.Inbox, Workshop.AgentEntry). Breaks "signals as backbone" principle. |
| `schema_interceptor.ex` | 92 | Signals | Mesh or Gateway | Validates/enriches `Mesh.DecisionLog`. Aliases `Mesh.*` types. Should not contain the word "entropy." |
| `protocol_tracker.ex` | 185 | Signals | Monitoring | Observability concern tracking message protocol hops. Imports `Infrastructure.AgentProcess` for stats. |
| `hitl_intervention_event.ex` | 85 | Signals | HITL/Infrastructure | Ash Resource persisting HITL audit records. HITL is its own concern, not a signal. |

### Boundary Smells (correctly placed but with violations)

| Module | Lines | Smell | Detail |
|--------|-------|-------|--------|
| `operations.ex` | 169 | Cross-domain call | `check_inbox`/`check_operator_inbox` actions call `Infrastructure.AgentProcess` directly inside Ash action run fns |
| `entropy_tracker.ex` | 217 | Semantic mismatch | Computes cognitive health (Mesh/Gateway concern) but lives in Signals. Clean aliases though. |
| `event_stream.ex` | 420 | Cross-domain import | `Workshop.AgentEntry.uuid?/1` for UUID format check. Should be a utility. |
| `event_stream/agent_lifecycle.ex` | -- | Implicit coupling | Shared ETS table names as bare atoms with no formal contract |
| `buffer.ex` | 54 | Transport leak | Direct `Phoenix.PubSub.broadcast` on "signals:feed" bypasses Signals.emit. UI topic in infra module. |
| `task_projection.ex` | 30 | Domain mismatch | Models Workshop/Factory concept (agent tasks) inside SignalBus domain |
| `tool_failure.ex` | 60 | Domain mismatch | Models monitoring concept (tool errors) inside SignalBus domain |

---

## 2. Function Shape Audit (5 Largest Files)

### catalog.ex (735 lines)

- All 8 public functions are pure. Shape clarity is excellent.
- `derive/1` is an escape valve that weakens the catalog's contract ("if not in catalog, emit raises" -- but derive silently creates entries). Should be documented as dynamic-signal-only.
- `by_category/1` returns `[{atom(), signal_def()}]` while `all/0` returns `%{atom() => signal_def()}` -- inconsistent return shapes.
- 735 lines is declarative data, not logic. Line count is not the problem; the 6 attribute groups could be separate modules for navigability.

### agent_watchdog.ex (474 lines)

- `:beat` handler orchestrates 4 distinct concerns: heartbeat, crash detection, escalation, pane scanning.
- Pure transformations correctly extracted to EscalationEngine and PaneScanner sub-modules.
- **`reassign_agent_tasks/2` is misplaced domain logic** -- crash recovery + task reassignment (Factory.Board mutations) inside a monitoring process. Should be an Oban job triggered by `:agent_crashed` signal.
- `maybe_unpause/2` has bare `catch :exit, _` swallowing failures silently.
- `safe_emit/2` checks `function_exported?` on every 5s tick -- always true at steady state.
- `check_pane_activity/2` buries an `AgentProcess.update_fields` ETS write side effect.

### event_stream.ex (420 lines)

- Three concerns in one GenServer: (1) ETS event buffer, (2) heartbeat liveness registry, (3) ingest pipeline coordinator.
- Heartbeat state in GenServer process state, events in ETS -- asymmetric query paths (`latest_session_state/1` is GenServer call, `list_events/0` is direct ETS read).
- `handle_channel_events/1` + `handle_pre_tool_use/3` is a growing tool-name dispatch table (6 clauses) inside the event buffer. Should be extracted to a `ToolInterceptor` module.
- `tombstoned?/1` mixes a pure check with a scheduled self-cast for expiry -- non-obvious side effect.
- `evict_candidate/3-4` is a well-designed custom max-heap fold. Could be extracted but small enough inline.

### entropy_tracker.ex (217 lines)

- `record_and_score/2` serializes through GenServer (correct -- private ETS).
- **`classify_and_store/8` is a shape smell** -- 8 parameters mixing classification (pure), ETS storage (effect), and signal emission (effect). Should decompose to: `classify/3` (pure) + `store/5` (effect) + `emit_transition/3` (effect).
- `build_alert_event/4` is misnamed -- it emits, doesn't build. Two of four params are unused (`_agent_id`, `_window`).
- `@spec` claims `{:error, :missing_agent_id}` but no code path returns it. Dead spec.
- `slide_window/2` uses `List.delete_at(window, 0)` (O(n)) instead of `tl/1` (O(1)). Window is small (5) so not a perf issue, but unidiomatic.
- Config reads (`Application.get_env` x3) on every call. Could be read once in init and stored in state.

### bus.ex (206 lines)

- `resolve/1` is clean pure multi-clause dispatch on string prefix -> tagged tuple.
- `normalize/3` is clean pure map builder.
- **`log_delivery/4` mixes two concerns** -- ETS write (message log) + `Signals.emit(:fleet_changed)`. The signal emission is unrelated to logging.
- `deliver_to_agent/2` has dual lookup path: `AgentProcess.alive?` then `Registry.lookup` fallback. Creates implicit coupling to both AgentProcess and Registry internals.
- `send/1` spec claims `{:error, String.t()}` but internal delivery path never surfaces errors. Only the guard clause (missing required keys) returns error.

---

## 3. Coupling Graph

### Cross-Domain Reference Matrix

| Signals Module | Infrastructure | Factory | Workshop | Operator | Mesh | Settings |
|---------------|---------------|---------|----------|----------|------|----------|
| `bus.ex` | AgentProcess, TeamSupervisor, Tmux | - | - | - | - | - |
| `from_ash.ex` | WebhookDelivery | Pipeline, PipelineTask, Project, CronJob | - | - | - | SettingsProject |
| `operations.ex` | AgentProcess | - | - | - | - | - |
| `agent_watchdog.ex` | AgentProcess, HITLRelay, Tmux | Board | AgentEntry | Inbox | - | - |
| `protocol_tracker.ex` | AgentProcess | - | - | - | - | - |
| `schema_interceptor.ex` | - | - | - | - | DecisionLog, DL.Helpers | - |
| `event_stream.ex` | - | - | AgentEntry | - | - | - |
| `pane_scanner.ex` | Tmux, Tmux.Ssh | - | - | - | - | - |

### Violations Ranked by Severity

| Rank | File | Violation | Domains Touched |
|------|------|-----------|----------------|
| 1 | `agent_watchdog.ex` | 6 cross-domain imports + direct Operator.Inbox write | Infrastructure, Factory, Workshop, Operator |
| 2 | `bus.ex` | Delivery authority owns Infrastructure transport logic | Infrastructure (3 modules) |
| 3 | `from_ash.ex` | Compile-time coupling to 4 domain module names | Factory (4), Infrastructure (1), Settings (1) |
| 4 | `schema_interceptor.ex` | Mesh types leak into Signals layer | Mesh (2 modules) |
| 5 | `pane_scanner.ex` | Scan logic reaches into transport internals | Infrastructure (2 modules) |

### No circular dependencies found. Graph is acyclic from compile-time alias perspective.

---

## 4. Priority Findings (Consolidated)

### Critical (Active boundary violations)

1. **AgentWatchdog is misplaced** -- orchestrates agent health across 6 domains from inside Signals. `reassign_agent_tasks/2` is Factory domain logic. Direct `Operator.Inbox.write` bypasses signals backbone.

2. **SchemaInterceptor is misplaced** -- validates `Mesh.DecisionLog` from inside Signals. Should not contain the word "entropy." Entropy scoring should happen through signal system, not direct coupling.

3. **ProtocolTracker is misplaced** -- monitoring/observability concern tracking protocol hops. Imports Infrastructure for stats.

### High (Shape smells requiring decomposition)

4. **`classify_and_store/8`** in EntropyTracker -- 8-arity function mixing 3 concerns (classify + store + emit). Dead spec (`{:error, :missing_agent_id}`).

5. **EventStream mixes 3 concerns** -- event buffer + heartbeat registry + ingest pipeline. `handle_channel_events` is a growing dispatch table inside a buffer.

6. **`log_delivery/4`** in Bus -- mixes ETS write with unrelated signal emission.

### Medium (Coupling that should be cleaned)

7. **Operations.ex** -- `check_inbox` actions call `Infrastructure.AgentProcess` directly inside Ash action run fns.

8. **EventStream imports `Workshop.AgentEntry`** -- for a UUID format check that should be a utility function.

9. **Buffer.ex** -- bypasses `Signals.emit` for "signals:feed" PubSub topic. UI concern in infra module.

10. **TaskProjection + ToolFailure** -- model Workshop/Factory and monitoring concepts inside SignalBus domain.

---

---

## 5. Architect Observations

### "events == signals, signals == topics"

The naming is confused. What the system calls "events" (hook events from agents), "signals" (PubSub broadcasts), and "topics" (PubSub channel strings) are three names for the same pipeline stage. The conceptual model should be:

- An **event** arrives from an external source (agent hook, HTTP gateway)
- It becomes a **signal** when emitted through the Signals system
- A signal is delivered on a **topic** (the PubSub transport detail)

EventStream, Event, EventPayload -- these are all signals-domain modules using the wrong vocabulary. The naming leak makes it harder to reason about boundaries.

### HITL Intervention Event is misplaced

`hitl_intervention_event.ex` is an Ash Resource persisting HITL audit records. HITL (Human-in-the-Loop) is its own concern -- pausing agents, buffering messages, operator approval/rejection. This Ash resource belongs with the HITL infrastructure, not in the Signals domain. The initial audit marked it "correct" because it's a clean Ash resource, but the boundary is wrong.

Same pattern as TaskProjection and ToolFailure: clean modules in the wrong domain.

### SchemaInterceptor should not contain "entropy"

Confirmed by architect. The entropy scoring side effect leaked into a validation module. EntropyTracker should observe events through the signal system (subscribe to `:new_event` or equivalent), not through a direct call from the interceptor.

---

---

## 6. PubSub System Architecture

### Signal Flow

```
Event source (agent hook, Ash notifier, GenServer)
  -> Ichor.Signals.emit(name, data)           [facade]
  -> Ichor.Signals.Runtime.emit(name, data)   [impl]
     -> Catalog.lookup!(name)                 [validate]
     -> Message.build(name, category, data)   [envelope]
     -> PubSub.broadcast("signal:{category}", message)
     -> PubSub.broadcast("signal:{category}:{name}", message)
     -> telemetry [:ichor, :signal, name]
```

### Topic Shapes

| Pattern | Example | Subscribe via |
|---------|---------|---------------|
| `"signal:{category}"` | `"signal:fleet"` | `Signals.subscribe(:fleet)` |
| `"signal:{category}:{name}"` | `"signal:fleet:agent_started"` | `Signals.subscribe(:agent_started)` |
| `"signal:{category}:{name}:{scope}"` | `"signal:agent:terminal_output:abc123"` | `Signals.subscribe(:terminal_output, "abc123")` |

### Raw PubSub Calls Outside Signals

Only 2 legitimate bypasses:
1. `Buffer` re-broadcasts on `"signals:feed"` for the /signals LiveView page
2. `PluginScaffold` subscribes to `"plugin:{app_name}"` for hot-reload

### Key Design Properties

- **Noop is the default fallback** -- if config key absent, signals silently drop (not crash)
- **Dual broadcast** -- every static signal goes to BOTH category topic AND signal-specific topic
- **Dynamic signals** require `dynamic: true` in catalog; scoped subscribe is required

---

## 7. Archon System Architecture

### Archon Data Flow

```
Signal fires -> SignalManager.handle_info
  -> ingest: update_counts -> update_latest -> resolve_attention -> add_attention
  -> State: %{signal_count, counts_by_category, latest_by_category, attention[max 25]}

Architect opens overlay -> DashboardArchonHandlers.handle_archon_toggle
  -> SignalManager.snapshot() + .attention() -> LiveView assigns

Architect types message -> handle_archon_send
  -> Task.start(fn -> Chat.chat(input, history) end)
  -> Chat builds LLMChain (OpenAI gpt-4o-mini) with AshAi tools
  -> Memory retrieval: MemoriesClient.search (edges + episodes, 2s timeout)
  -> LLMChain.run(mode: :while_needs_response)
  -> LLM calls Ash tools -> actions execute -> LLM synthesizes response
  -> {:archon_response, result} sent to LiveView PID
```

### Archon's Tool Set (via AshAi)

| Resource | Actions |
|----------|---------|
| Workshop.Agent | list_live_agents, agent_status, stop_agent, pause_agent, resume_agent |
| Workshop.ActiveTeam | list_teams |
| Signals.Operations | recent_messages, operator_send_message, agent_events, check_operator_inbox |
| Infrastructure.Operations | system_health, tmux_sessions, sweep |
| Archon.Manager | manager_snapshot, attention_queue, discovery_catalog, discovery_domain |
| Factory.Project | list_projects, create_project |
| Factory.Floor | mes_status, cleanup_mes |
| Archon.Memory | remember |

### Key Properties

- **SignalManager is read-only** -- ingests all signals, builds attention queue, never acts
- **TeamWatchdog is a pure signal emitter** -- never inserts Oban directly, emits cleanup signals for downstream dispatchers
- **Operator Inbox is file-based** -- JSON files in `~/.claude/inbox/`, not PubSub. Persists across restarts.
- **LLM never subscribes to signals** -- it queries synchronously via Ash actions

### Gap: No Signal -> Archon Action Pipeline

SignalManager sees every signal and classifies attention items, but **nothing triggers Archon to act**. The attention queue is passive -- it waits for the human to open the overlay and look. There is no autonomous signal -> diagnosis -> healing loop.

---

## 8. Holistic Synthesis

### The Core Problem

The Signals domain (`lib/ichor/signals/`) has become a dumping ground. 3243 lines across 20+ files, but only ~40% is actual signal infrastructure (Runtime, Catalog, Topics, Message, Behaviour, Buffer). The rest is:

- **Monitoring/health** (AgentWatchdog, EntropyTracker, ProtocolTracker) -- concerns that USE signals but are not ABOUT signals
- **Data projections** (EventStream, TaskProjection, ToolFailure) -- views over event data that belong closer to their consuming domains
- **Gateway validation** (SchemaInterceptor) -- Mesh protocol validation that leaked into Signals
- **HITL audit** (HITLInterventionEvent) -- persistence concern for a separate domain
- **Delivery** (Bus, Operations) -- message delivery that couples Signals to Infrastructure internals

### The Naming Confusion

The codebase uses "events," "signals," and "topics" interchangeably:
- `EventStream` stores hook events but lives in signals/
- `Event` is an Ash action-only resource that wraps signal operations
- `EventPayload` is a struct for hook event data
- `Topics` is about PubSub channels

These are three stages of the same pipeline (ingestion -> broadcast -> subscription) using three different names.

### What Belongs in Signals (Signal Infrastructure)

| Module | Why |
|--------|-----|
| `signals.ex` (facade) | Public API |
| `signals/behaviour.ex` | Contract |
| `signals/runtime.ex` | PubSub transport |
| `signals/noop.ex` | Test impl |
| `signals/catalog.ex` (+ split into catalog/) | Signal registry |
| `signals/topics.ex` | Topic naming |
| `signals/message.ex` | Envelope struct |
| `signals/handler.ex` (new) | Handler behaviour |
| `signals/buffer.ex` | Signal stream fan-out for UI |
| `signals/from_ash.ex` | Notifier adapter (cross-domain by design) |

### What Should Move Out

| Module | Current | Proposed Home | Reason |
|--------|---------|---------------|--------|
| `agent_watchdog.ex` + sub/ | signals/ | Infrastructure or Archon | Agent health orchestration, 6 cross-domain imports |
| `schema_interceptor.ex` | signals/ | Mesh or Gateway | Validates Mesh.DecisionLog, contains "entropy" |
| `protocol_tracker.ex` | signals/ | Monitoring or Infrastructure | Protocol hop tracing, imports AgentProcess |
| `entropy_tracker.ex` | signals/ | Mesh or Archon | Cognitive health scoring, Gateway concern |
| `hitl_intervention_event.ex` | signals/ | HITL or Infrastructure | Persists HITL audit records |
| `event_stream.ex` + sub/ | signals/ | Infrastructure or own domain | Event buffer + heartbeat registry + ingest pipeline |
| `task_projection.ex` | signals/ | Workshop or Factory | Models agent tasks |
| `tool_failure.ex` | signals/ | Monitoring | Models tool errors |
| `operations.ex` | signals/ | SignalBus (keep but fix) | cross-domain AgentProcess calls in action runs |
| `event.ex` | signals/ | SignalBus (keep) | Ash facade, rename consideration |
| `event_payload.ex` | signals/ | Depends on EventStream destination | Hook event struct |

### The Handler Behaviour as Unifying Pattern

Instead of adding more GenServer subscribers for each new reactive concern (entropy healing, crash recovery, protocol monitoring), the **Handler behaviour** provides a single dispatch mechanism:

1. Any signal can register a handler module in its catalog entry
2. `Signals.emit/2` calls the handler at emit-time (after PubSub broadcast)
3. Handlers spawn async for long-running work
4. No new GenServer needed per concern

This replaces the pattern of "create a GenServer, subscribe to signals, handle_info pattern match, dispatch" with "implement Handler, register in catalog."

### The Bus Boundary Question

`Bus.send/1` is the message delivery authority but it directly calls `AgentProcess`, `TeamSupervisor`, and `Tmux`. This couples Signals to Infrastructure transport. Two options:
1. Bus stays in Signals as the delivery facade, accepting the Infrastructure coupling
2. Bus moves to Infrastructure where transport belongs

Bus is used by: `Operations.agent_send_message`, `Operations.operator_send_message`, `AgentWatchdog` (nudge). All callers are either in Signals or should move out. If AgentWatchdog moves out, the only callers are Operations actions. Bus could stay as a thin facade if Infrastructure provides a delivery API.

### Priority Sequence

1. **Handler behaviour** -- enables entropy healing without new GenServers
2. **Catalog split** -- navigability, enables handler registration per signal group
3. **SignalManager split** -- attention rules + summaries extracted for maintainability
4. **EntropyTracker.Healer** -- first handler implementation
5. **SchemaInterceptor boundary fix** -- remove entropy coupling
6. **Module relocations** -- AgentWatchdog, ProtocolTracker, HITL, etc. (separate wave)
