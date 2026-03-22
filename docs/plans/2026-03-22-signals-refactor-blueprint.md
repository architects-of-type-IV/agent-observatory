# Signals Refactor -- Shape Fixes

**Date**: 2026-03-22
**Status**: Design v3
**Method**: Read every file, list what's wrong with the shapes, fix them.

---

## File-by-file findings

### `entropy_tracker.ex` -- 5 shape problems

1. **`classify_and_store/8`** -- 8 params. Each clause ignores 2-3 of them. Does three things: classify score against thresholds (pure), emit signal (side effect), ETS insert (side effect).
   - **Fix**: Split into `classify(score, loop_threshold, warning_threshold) :: :loop | :warning | :normal`, `emit_state_change(session_id, severity, prior_severity)`, `store(table, session_id, window, severity, agent_id)`.

2. **`build_alert_event/4`** -- Named "build" but calls `Signals.emit`. 2 of 4 params unused. It's one line.
   - **Fix**: Inline `Signals.emit(:entropy_alert, %{session_id: session_id, entropy_score: score})` at the call site. Delete the function.

3. **`slide_window/2`** -- `List.delete_at(window, 0)` is O(n). `tl(window)` is O(1). Window is small but the idiom is wrong.
   - **Fix**: `tl(window)`.

4. **`@spec` for `record_and_score/2`** -- Claims `{:error, :missing_agent_id}` return. No clause returns it.
   - **Fix**: Remove `| {:error, :missing_agent_id}` from spec.

5. **`read_config/2`** -- Called 3x per `record_and_score`. Config values don't change between calls. The `if is_number(value)` guard with Logger warning runs on every single event.
   - **Fix**: Read thresholds once in `init/1`, store in state. Add a `handle_cast(:reload_config, ...)` for runtime changes if genuinely needed.

### `schema_interceptor.ex` -- 1 problem

6. **`alias Ichor.Signals.EntropyTracker`** -- Validation module calling a GenServer synchronously to score entropy. Side effect (ETS write + signal emission) inside a validation function.
   - **Fix**: EntropyTracker subscribes to `:events` (`:new_event`). Scores events from `handle_info`. SchemaInterceptor becomes pure validation: `validate_and_enrich/1` -> `DLHelpers.from_json(params)`. Remove `enrich_with_entropy/1`, `extract_entropy_fields/1`, and the `EntropyTracker` alias entirely.
   - **Also**: `EventBridge` line 236 calls `EntropyTracker.register_agent/2` directly. Same fix -- EntropyTracker self-registers from `:new_event` data.

### `event_stream.ex` -- 4 problems

7. **Three concerns in one GenServer**: Event buffer (ETS), heartbeat liveness (GenServer state), tool interception (channel dispatch). These share a process boundary for no reason.
   - **Fix (later wave)**: Extract heartbeat into its own GenServer. Extract tool interception into a module that `ingest_event/1` calls. EventStream becomes just the buffer + ingest normalizer.

8. **`resolve_session_id/2`** imports `Workshop.AgentEntry.uuid?/1` for a UUID check.
   - **Fix**: Replace with `String.match?(raw_id, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)` or a one-line private `uuid?/1`. Delete the Workshop import.

9. **`tombstoned?/1`** -- Predicate that casts to self as a side effect. `tombstoned?` should return true/false. Expiry scheduling is a separate concern.
   - **Fix**: `tombstoned?/1` returns boolean only. Caller schedules expiry separately.

10. **`emit_intercepted/4` and `emit_intercepted_mcp/2`** -- Same shape (emit `:agent_message_intercepted`), different field extraction.
    - **Fix**: One `emit_intercepted/1` that takes a normalized map. Two extractors: `extract_send_message_fields/2`, `extract_mcp_fields/2`.

### `protocol_tracker.ex` -- 2 problems

11. **`maybe_create_trace/2`** -- 3 clauses building identical `%{id, type, from, to, content_preview, message_type, timestamp, hops}` structs. They differ by: `:send_message` vs `:team_create` vs `:agent_spawn`, and which payload fields to read.
    - **Fix**: One `build_trace/2` function. Pattern match on event type to extract the variable fields. The struct shape is the same.

12. **`compute_stats/0`** -- Calls `AgentProcess.list_all()` just for `length()`.
    - **Fix**: Keep for now. The cross-module read is for a count. Low priority.

### `operations.ex` -- 1 problem

13. **`check_inbox` and `check_operator_inbox`** -- Nearly identical. One takes `session_id` from args, other hardcodes `"operator"`.
    - **Fix**: One function, `session_id` defaults to `"operator"`. Or keep separate for API clarity but extract the shared body.

14. **Message key normalization** in `check_operator_inbox` -- `message[:from] || message["from"]`. Messages should have consistent keys upstream.
    - **Fix**: Normalize in `AgentMessage` when recording. Not here.

### `catalog.ex` -- navigability

15. **735 lines** of declarative data. The functions (46 lines) are fine. The data maps are fine. It's just long.
    - **Fix**: Split the 6 `@*_defs` map literals into `catalog/{core,gateway,monitoring,mes,pipeline,cleanup}.ex`. Each exposes `defs/0`. Aggregator merges at compile time.
    - **Risk**: Compile order. Mix resolves it because the aggregator references sub-modules in its body. Add a test for duplicate keys.

### Files that are fine

- `behaviour.ex` -- 12 lines, callbacks. Clean.
- `signals.ex` -- facade, delegates to impl. Clean.
- `runtime.ex` -- PubSub transport. Clean.
- `topics.ex` -- 3 pure functions. Clean.
- `message.ex` -- struct + build. Clean.
- `noop.ex` -- test impl. Clean.
- `buffer.ex` -- ring buffer, 54 lines. Clean.
- `from_ash.ex` -- notifier adapter. Clean pattern matching.
- `event.ex` -- Ash action-only resource. Clean (name could be better).
- `task_projection.ex` -- Simple data layer resource. Clean.
- `tool_failure.ex` -- Simple data layer resource. Clean.
- `hitl_intervention_event.ex` -- Clean Ash resource. Wrong folder but code is fine.
- `event_payload.ex` -- Actually `TraceEvent` struct. Clean.

---

## What to add: Handler behaviour

Signals = PubSub. Subscribers run actions. Currently adding a subscriber means a new GenServer. A `Handler` behaviour lets signals trigger actions at emit-time without new processes.

```elixir
# handler.ex
@callback handle(atom(), map()) :: :ok
```

Registered in catalog entries as `handler: Module`. Called from the `Signals` facade after `impl().emit()`. Rescue + telemetry on error. Handlers spawn async for long work.

First use: entropy signals trigger Archon with a signal-specific prompt. The handler builds context and calls `Archon.Chat.chat/2` via Task.Supervisor. Archon decides what to do. No "Healer" entity.

---

## Execution order

### Wave 1: Fix shapes (no moves, no new files except handler.ex)

| # | Fix | File | Effort |
|---|-----|------|--------|
| 1 | Decompose `classify_and_store/8` | entropy_tracker.ex | small |
| 2 | Inline `build_alert_event/4` | entropy_tracker.ex | tiny |
| 3 | `tl()` instead of `List.delete_at` | entropy_tracker.ex | tiny |
| 4 | Remove dead spec | entropy_tracker.ex | tiny |
| 5 | Config in init, not per-call | entropy_tracker.ex | small |
| 6 | Remove entropy from SchemaInterceptor | schema_interceptor.ex + entropy_tracker.ex | medium |
| 7 | Remove EntropyTracker.register_agent from EventBridge | event_bridge.ex + entropy_tracker.ex | small |
| 8 | Replace AgentEntry.uuid? with inline check | event_stream.ex | tiny |
| 9 | Pure `tombstoned?/1` | event_stream.ex | small |
| 10 | Merge `emit_intercepted` variants | event_stream.ex | small |
| 11 | Merge `maybe_create_trace` clauses | protocol_tracker.ex | small |
| 12 | Create handler.ex behaviour | signals/ | small |
| 13 | Add handler dispatch to facade | signals.ex | small |
| 14 | Split catalog into catalog/ | catalog.ex | medium |

### Wave 2: Entropy handler + SignalManager split

- Add handler registration to entropy catalog entries
- Create entropy handler module (trigger for Archon)
- Add intervention tracking to EntropyTracker state
- Split signal_manager.ex into signal_manager/{attention,summary}.ex
- Add entropy signals to attention queue

### Wave 3: Move files to correct locations

After shapes are clean, moves are mechanical alias updates:
- HITLInterventionEvent -> infrastructure/hitl/
- AgentWatchdog + sub/ -> infrastructure/fleet/
- SchemaInterceptor -> mesh/
- ProtocolTracker -> infrastructure/fleet/
- EntropyTracker + handler -> mesh/

### Wave 4: Remaining cleanup

- EventStream concern separation (heartbeat, tool interception)
- Operations.ex `check_inbox` dedup
- Message key normalization upstream

---

## Verification per wave

1. `mix compile --warnings-as-errors`
2. `mix test`
3. Signal count unchanged: `Catalog.all() |> map_size()`
