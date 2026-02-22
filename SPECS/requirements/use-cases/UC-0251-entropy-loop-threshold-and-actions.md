---
id: UC-0251
title: Classify Session as LOOP and Emit EntropyAlertEvent
status: draft
parent_fr: FR-9.4
adrs: [ADR-018]
---

# UC-0251: Classify Session as LOOP and Emit EntropyAlertEvent

## Intent
When `record_and_score/2` computes an entropy score strictly less than the configured LOOP threshold (default `0.25`), `EntropyTracker` must atomically perform three actions in the same call: broadcast an `EntropyAlertEvent` to `"gateway:entropy_alerts"`, broadcast a topology state update setting the node to `:alert_entropy` on `"gateway:topology"`, and return `{:ok, score, :loop}` to `SchemaInterceptor`. The LOOP threshold is read from application config on every call so it takes effect without a process restart.

## Primary Actor
`Observatory.Gateway.EntropyTracker`

## Supporting Actors
- Phoenix PubSub topic `"gateway:entropy_alerts"` (receives `EntropyAlertEvent`)
- Phoenix PubSub topic `"gateway:topology"` (receives node state update)
- `SchemaInterceptor` (receives `{:ok, score, :loop}` return value)
- Application config (`Application.get_env(:observatory, :entropy_loop_threshold, 0.25)`)

## Preconditions
- `EntropyTracker` GenServer is running.
- The session's sliding window contains at least one entry.
- The computed uniqueness ratio is strictly less than `0.25` (or the runtime-configured threshold).

## Trigger
`SchemaInterceptor` calls `EntropyTracker.record_and_score/2` and the uniqueness ratio computation returns a value below the LOOP threshold.

## Main Success Flow
1. `record_and_score/2` computes a score of `0.2` for session `"sess-loop"`.
2. `EntropyTracker` reads `Application.get_env(:observatory, :entropy_loop_threshold, 0.25)` and gets `0.25`.
3. `0.2 < 0.25` is true — LOOP classification applies.
4. An `EntropyAlertEvent` is constructed with all required fields (see FR-9.7) and broadcast to `"gateway:entropy_alerts"`.
5. A topology update map with `state: "alert_entropy"` for the affected node is broadcast to `"gateway:topology"`.
6. `record_and_score/2` returns `{:ok, 0.2, :loop}` to the caller.
7. `SchemaInterceptor` sets `cognition.entropy_score: 0.2` in the outbound DecisionLog envelope.

## Alternate Flows
### A1: Score is exactly 0.25
Condition: The computed score equals the threshold exactly.
Steps:
1. `0.25 < 0.25` is false — LOOP does not apply.
2. `EntropyTracker` evaluates the WARNING threshold next (see FR-9.5).
3. No `EntropyAlertEvent` is emitted for this call.

## Failure Flows
### F1: EntropyTracker cannot determine agent_id for the session
Condition: No DecisionLog message carrying an `agent_id` has been received for the session.
Steps:
1. `EntropyTracker` cannot construct a valid `EntropyAlertEvent` (missing `agent_id` field).
2. The event is NOT broadcast.
3. `EntropyTracker` logs a warning and returns `{:error, :missing_agent_id}`.
Result: The caller receives an error; entropy overwrite does not occur; schema violation log entry is emitted.

## Gherkin Scenarios

### S1: Score below LOOP threshold triggers EntropyAlertEvent and topology update
```gherkin
Scenario: Score of 0.2 triggers LOOP classification with all three required actions
  Given session "sess-loop" has a sliding window producing a uniqueness ratio of 0.2
  And the entropy_loop_threshold config is 0.25
  When record_and_score/2 is called for session "sess-loop"
  Then an EntropyAlertEvent is broadcast to "gateway:entropy_alerts"
  And a topology update with state "alert_entropy" is broadcast to "gateway:topology"
  And record_and_score/2 returns {:ok, 0.2, :loop}
```

### S2: Score exactly at threshold is not classified as LOOP
```gherkin
Scenario: Score of exactly 0.25 does not trigger LOOP classification
  Given session "sess-warn" has a sliding window producing a uniqueness ratio of 0.25
  And the entropy_loop_threshold config is 0.25
  When record_and_score/2 is called for session "sess-warn"
  Then no EntropyAlertEvent is broadcast to "gateway:entropy_alerts"
  And record_and_score/2 does not return {:ok, 0.25, :loop}
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that seeds a session window with 5 identical tuples (score `0.2`) and asserts `record_and_score/2` returns `{:ok, 0.2, :loop}`, an `EntropyAlertEvent` is published to `"gateway:entropy_alerts"`, and a topology broadcast with `state: "alert_entropy"` is published to `"gateway:topology"`.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that seeds a session window with a score of exactly `0.25` and asserts the return value is not `{:ok, _, :loop}` and no `EntropyAlertEvent` is published.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** Session sliding window with uniqueness ratio < 0.25; runtime config `entropy_loop_threshold`.
**Outputs:** `EntropyAlertEvent` on `"gateway:entropy_alerts"`; topology state update on `"gateway:topology"`; `{:ok, score, :loop}` return value.
**State changes:** PubSub messages published; caller's outbound DecisionLog `cognition.entropy_score` overwritten.

## Traceability
- Parent FR: FR-9.4
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md)
