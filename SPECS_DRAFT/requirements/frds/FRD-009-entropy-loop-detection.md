---
id: FRD-009
title: Entropy Loop Detection Functional Requirements
date: 2026-02-22
status: draft
source_adr: [ADR-018, ADR-015, ADR-021]
related_rule: []
---

# FRD-009: Entropy Loop Detection

## Purpose

The Entropy Loop Detection subsystem provides an objective, Gateway-computed signal that identifies when an agent is caught in a repetitive reasoning loop. Rather than relying on agent self-reporting — which is unreliable when the agent is the source of the loop — the Gateway maintains a sliding window of recent `{intent, action.tool_call, action.status}` tuples per session and computes a uniqueness ratio. When that ratio falls below configured thresholds, the system emits a structured alert event, updates the topology map node state, and exposes a one-click operator intervention path.

The subsystem is designed to operate with microsecond-level overhead per incoming message so it does not introduce latency on the critical Gateway path. All thresholds and window sizes are runtime-configurable to allow tuning without redeployment.

## Functional Requirements

### FR-9.1: Module Location

`Observatory.Gateway.EntropyTracker` MUST be implemented in `lib/observatory/gateway/entropy_tracker.ex`. The module MUST be a GenServer or a module backed by ETS-per-session state that survives individual message processing without resetting. It MUST export a minimum public API of `EntropyTracker.record_and_score/2`. No other module in the codebase MAY maintain per-session entropy state; `EntropyTracker` is the single authoritative owner of sliding window data.

**Positive path**: `SchemaInterceptor` calls `EntropyTracker.record_and_score("sess-abc", tuple)` after validating a DecisionLog message; `EntropyTracker` records the tuple in the session's window and returns `{:ok, score}`.

**Negative path**: Any module other than `SchemaInterceptor` attempts to write entropy tuples directly to ETS, bypassing `EntropyTracker`; this MUST be prevented by keeping the ETS table private to the `EntropyTracker` process (table owner is the GenServer pid).

---

### FR-9.2: Sliding Window Data Structure

`EntropyTracker` MUST maintain one sliding window per session_id. Each window MUST hold the last 5 `{intent, tool_call, action_status}` tuples received for that session in insertion order. When a sixth tuple is added, the oldest tuple MUST be evicted so the window size never exceeds 5. The window MUST be stored in a data structure that supports O(1) append and O(1) eviction from the head (a queue or circular buffer is appropriate). Window state MUST persist in ETS keyed by `session_id` so that multiple sequential calls to `record_and_score/2` for the same session accumulate correctly.

**Positive path**: Five tuples have been recorded for session "sess-abc"; a sixth tuple arrives; the first tuple is evicted; the window contains tuples 2 through 6; the entropy score is recomputed over this new window.

**Negative path**: A session's window contains fewer than 5 entries (e.g., only 3 tuples received so far); `EntropyTracker` MUST compute the uniqueness ratio over the available N entries (N = 3 in this case) rather than waiting for a full window; the score is returned normally.

---

### FR-9.3: Uniqueness Ratio Computation

`EntropyTracker` MUST compute the entropy score as `unique_count / window_size`, where `unique_count` is the number of distinct `{intent, tool_call, action_status}` tuples in the current window and `window_size` is the total number of tuples in the window. A score of `0.0` indicates a pure loop (all tuples identical); a score of `1.0` indicates all tuples are unique. The computation MUST be performed using exact tuple equality (no fuzzy matching or string similarity) and MUST complete within the same process call as `record_and_score/2` — no async computation is permitted. The computed score MUST be returned as a float rounded to 4 decimal places.

**Positive path**: Window contains `[{:search, "read_file", :failure}, {:search, "read_file", :failure}, {:search, "read_file", :failure}, {:search, "read_file", :failure}, {:search, "read_file", :failure}]`; unique_count = 1, window_size = 5; score = 0.2; function returns `{:ok, 0.2}`.

**Negative path**: Window contains 5 completely different tuples; unique_count = 5, window_size = 5; score = 1.0; no alert is emitted.

---

### FR-9.4: LOOP Threshold and Resulting Actions

When the computed entropy score is strictly less than `0.25`, `EntropyTracker` MUST classify the session as `LOOP` severity and MUST perform three actions atomically within the same `record_and_score/2` call: (1) construct and broadcast an `EntropyAlertEvent` to the PubSub topic `"gateway:entropy_alerts"`; (2) update the affected node's state to `:alert_entropy` in the topology map by broadcasting to `"gateway:topology"` with the node's `state` field set to `"alert_entropy"`; (3) return `{:ok, score, :loop}` to the caller so `SchemaInterceptor` can record the severity in the DecisionLog envelope. The `LOOP` threshold of `0.25` MUST be read from application config at runtime via `Application.get_env(:observatory, :entropy_loop_threshold, 0.25)`.

**Positive path**: `record_and_score/2` computes a score of `0.2`; entropy is below 0.25; `EntropyAlertEvent` is broadcast to `"gateway:entropy_alerts"`; a topology update setting `state: "alert_entropy"` is broadcast to `"gateway:topology"`; the function returns `{:ok, 0.2, :loop}`.

**Negative path**: Score is exactly `0.25`; this is NOT below the LOOP threshold; no `EntropyAlertEvent` is emitted; the session is classified as WARNING (see FR-9.5).

---

### FR-9.5: WARNING Threshold and Behavior

When the computed entropy score is greater than or equal to `0.25` and strictly less than `0.50`, `EntropyTracker` MUST classify the session as `WARNING` severity. In WARNING state, `EntropyTracker` MUST update the affected node's state to `:blocked` color rendering (amber, `#f59e0b`) via a topology broadcast and MUST return `{:ok, score, :warning}` to the caller. `EntropyTracker` MUST NOT emit an `EntropyAlertEvent` for WARNING severity — no alert is sent to `"gateway:entropy_alerts"`. The WARNING upper threshold of `0.50` MUST be read from application config at runtime via `Application.get_env(:observatory, :entropy_warning_threshold, 0.50)`.

**Positive path**: Score is `0.4`; severity is WARNING; node state is set to `:blocked` (amber) in a topology broadcast; `{:ok, 0.4, :warning}` is returned; no `EntropyAlertEvent` is published.

**Negative path**: Score drops from WARNING (`0.35`) to LOOP (`0.18`) on the next tuple; `EntropyTracker` correctly upgrades severity and emits an `EntropyAlertEvent` — prior WARNING state MUST NOT suppress the LOOP alert.

---

### FR-9.6: Normal Range

When the computed entropy score is greater than or equal to `0.50`, `EntropyTracker` MUST classify the session as Normal. In Normal state, `EntropyTracker` MUST take no alerting or topology state-change action. If the session was previously in WARNING or LOOP state and the score recovers to `>= 0.50`, `EntropyTracker` MUST broadcast a topology update resetting the node state to `:active` (or `:idle`, reflecting the node's actual operational state at that moment). The function MUST return `{:ok, score, :normal}`.

**Positive path**: Score is `0.8`; severity is Normal; no PubSub broadcast is emitted for alerts; node state reverts to `:active`; `{:ok, 0.8, :normal}` is returned.

**Negative path**: Score is exactly `0.50`; this meets the Normal lower bound; the session MUST be classified as Normal with no alert.

---

### FR-9.7: EntropyAlertEvent Fields

Every `EntropyAlertEvent` broadcast to `"gateway:entropy_alerts"` MUST be a map containing the following fields: `event_type` (string, value `"entropy_alert"`), `session_id` (string), `agent_id` (string), `entropy_score` (float), `window_size` (integer, value `5` or the actual window size if fewer than 5 tuples have been received), `repeated_pattern` (map with keys `intent` (string), `tool_call` (string), `action_status` (string) representing the most frequently occurring tuple in the window), and `occurrence_count` (integer, count of the most frequently occurring tuple). All fields MUST be present; any `EntropyAlertEvent` with a missing field MUST be rejected by the broadcaster before publishing.

**Positive path**: Window contains 5 tuples with 4 occurrences of `{:search, "list_files", :failure}`; `EntropyAlertEvent` is broadcast with `repeated_pattern: %{intent: "search", tool_call: "list_files", action_status: "failure"}` and `occurrence_count: 4`.

**Negative path**: `EntropyTracker` cannot determine `agent_id` for the session (e.g., no DecisionLog has been received that carries agent_id for this session); the event MUST NOT be broadcast; `EntropyTracker` MUST log a warning and return `{:error, :missing_agent_id}` to the caller.

---

### FR-9.8: Gateway Authoritative entropy_score

The Gateway MUST overwrite the `cognition.entropy_score` field in the DecisionLog envelope before broadcasting the message to downstream subscribers. The value written MUST be the float returned by `EntropyTracker.record_and_score/2` for that session. Agent self-reported values in `cognition.entropy_score` MUST be discarded and replaced by the Gateway-computed value. This overwrite MUST occur in `SchemaInterceptor` after validation and after `record_and_score/2` is called, so that the authoritative score is present in every outbound DecisionLog message. The original agent-reported value MUST NOT be preserved in any field of the outbound message.

**Positive path**: An agent sends a DecisionLog with `cognition.entropy_score: 0.9` (self-reported as healthy); `EntropyTracker` computes `0.15` for the session; `SchemaInterceptor` sets `cognition.entropy_score: 0.15` in the outbound envelope before broadcasting; the downstream consumer receives `0.15`.

**Negative path**: `EntropyTracker.record_and_score/2` returns an error (e.g., `{:error, :missing_agent_id}`); `SchemaInterceptor` MUST NOT overwrite `cognition.entropy_score` with the error tuple; it MUST retain the original agent-reported value and emit a `schema_violation` log entry noting the failed entropy computation.

---

### FR-9.9: SchemaInterceptor Call Contract

`SchemaInterceptor` MUST call `EntropyTracker.record_and_score/2` with arguments `(session_id :: String.t(), tuple :: {intent :: String.t(), tool_call :: String.t(), action_status :: atom()})` after each successful schema validation of a DecisionLog message. `record_and_score/2` MUST be called synchronously in the same process; it MUST NOT be dispatched via `Task.async` or cast. The return value `{:ok, score, severity}` MUST be used by `SchemaInterceptor` to overwrite `cognition.entropy_score` (per FR-9.8) and to set any derived node state broadcasts. `EntropyTracker.record_and_score/2` MUST NOT be called for messages that fail schema validation — entropy state MUST only reflect valid cognition events.

**Positive path**: A DecisionLog message passes schema validation in `SchemaInterceptor`; `EntropyTracker.record_and_score("sess-abc", {"plan", "write_file", :success})` is called; `{:ok, 0.6, :normal}` is returned; `SchemaInterceptor` sets `cognition.entropy_score: 0.6` and broadcasts the message.

**Negative path**: A DecisionLog message fails schema validation (e.g., missing required field); `SchemaInterceptor` rejects the message and MUST NOT call `EntropyTracker.record_and_score/2`; the session's sliding window is not updated.

---

### FR-9.10: gateway:entropy_alerts PubSub Topic

All `EntropyAlertEvent` messages MUST be broadcast to the PubSub topic `"gateway:entropy_alerts"`. The Session Cluster Manager LiveView MUST subscribe to `"gateway:entropy_alerts"` during `mount/3`. On receipt of an `EntropyAlertEvent`, the Session Cluster Manager MUST render the affected session in an "Entropy Alerts" panel and MUST display a "Pause and Inspect" button for that session. Clicking the "Pause and Inspect" button MUST issue a `Pause` command to the HITL API (ADR-021) for the associated `session_id`. No other UI component MAY subscribe to `"gateway:entropy_alerts"` in Phase 1; the Fleet Command topology map node state change is communicated via `"gateway:topology"` (see FR-9.4).

**Positive path**: `EntropyAlertEvent` is broadcast to `"gateway:entropy_alerts"` with `session_id: "sess-xyz"`; Session Cluster Manager receives it and renders "sess-xyz" in the Entropy Alerts panel with a "Pause and Inspect" button; the operator clicks the button; a Pause HITL command is issued for "sess-xyz".

**Negative path**: A second `EntropyAlertEvent` arrives for the same session within 5 seconds; the Session Cluster Manager MUST deduplicate by `session_id` in the Entropy Alerts panel — the session MUST appear only once in the panel regardless of how many alerts are received.

---

### FR-9.11: Runtime Configuration of Thresholds and Window Size

The sliding window size and both alert thresholds MUST be runtime-configurable via `Application.get_env/3` with defaults. The window size MUST be read as `Application.get_env(:observatory, :entropy_window_size, 5)`. The LOOP threshold MUST be read as `Application.get_env(:observatory, :entropy_loop_threshold, 0.25)`. The WARNING threshold MUST be read as `Application.get_env(:observatory, :entropy_warning_threshold, 0.50)`. `EntropyTracker` MUST read these values on each call to `record_and_score/2` rather than caching them at startup, so that configuration changes applied via `Application.put_env/3` (e.g., in tests or via a runtime config UI) take effect on the next processed message without restarting the process.

**Positive path**: A test sets `Application.put_env(:observatory, :entropy_loop_threshold, 0.30)`; the next call to `record_and_score/2` reads `0.30` as the LOOP threshold; a score of `0.28` now triggers LOOP severity instead of WARNING.

**Negative path**: An invalid value (e.g., a string `"high"`) is set for `entropy_loop_threshold` via `Application.put_env/3`; `EntropyTracker` MUST detect the invalid type, log a warning, fall back to the default `0.25`, and continue processing without crashing.

## Out of Scope (Phase 1)

- Option C hybrid: agent self-report + Gateway divergence events
- Natural language similarity comparison of `reasoning_chain` fields
- Per-agent (cross-session) entropy aggregation
- Entropy trend history beyond the current 5-tuple window
- Automatic session termination on LOOP detection (human operator retains control via HITL)
- Entropy alerting for messages that fail schema validation

## Related ADRs

- [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md) -- Entropy Score as Loop Detection Primitive; defines the uniqueness ratio algorithm, sliding window, alert thresholds, EntropyAlertEvent structure, and Gateway authoritative scoring
- [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md) -- Gateway Schema Interceptor; defines the SchemaInterceptor module that calls EntropyTracker.record_and_score/2
- [ADR-021](../../decisions/ADR-021-hitl-intervention-api.md) -- HITL Manual Intervention API; defines the Pause command issued when the operator clicks "Pause and Inspect"
