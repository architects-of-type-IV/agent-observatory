---
id: UC-0252
title: Classify Session as Normal and Reset Topology State on Recovery
status: draft
parent_fr: FR-9.6
adrs: [ADR-018]
---

# UC-0252: Classify Session as Normal and Reset Topology State on Recovery

## Intent
When `record_and_score/2` computes an entropy score of `>= 0.50`, `EntropyTracker` classifies the session as Normal and takes no alerting action. If the session was previously in WARNING or LOOP state, `EntropyTracker` must broadcast a topology update resetting the node state to `:active` (or `:idle` if the node is not currently processing) to clear the visual alert indicator. The function returns `{:ok, score, :normal}`.

## Primary Actor
`Observatory.Gateway.EntropyTracker`

## Supporting Actors
- Phoenix PubSub topic `"gateway:topology"` (receives node state reset broadcast only on recovery)
- `SchemaInterceptor` (receives `{:ok, score, :normal}` return value)
- Application config (`Application.get_env(:observatory, :entropy_warning_threshold, 0.50)`)

## Preconditions
- `EntropyTracker` GenServer is running.
- The session's sliding window contains at least one entry.
- The computed uniqueness ratio is `>= 0.50`.

## Trigger
`SchemaInterceptor` calls `EntropyTracker.record_and_score/2` and the computed uniqueness ratio meets or exceeds the WARNING upper threshold.

## Main Success Flow
1. `record_and_score/2` computes a score of `0.8` for session `"sess-healthy"`.
2. `EntropyTracker` reads `Application.get_env(:observatory, :entropy_warning_threshold, 0.50)` and gets `0.50`.
3. `0.8 >= 0.50` is true — Normal classification applies.
4. No `EntropyAlertEvent` is broadcast to `"gateway:entropy_alerts"`.
5. No topology state-change broadcast is emitted (session was already in normal state).
6. `record_and_score/2` returns `{:ok, 0.8, :normal}`.

## Alternate Flows
### A1: Session recovers from LOOP state to Normal
Condition: The session was previously classified as LOOP (score < 0.25) and the new score is 0.6.
Steps:
1. `record_and_score/2` computes a score of `0.6`.
2. Normal classification applies.
3. `EntropyTracker` detects that the prior state was LOOP (tracked in ETS alongside the window).
4. A topology update is broadcast to `"gateway:topology"` with `state: "active"` to reset the red flashing node.
5. `{:ok, 0.6, :normal}` is returned.

### A2: Score is exactly 0.50
Condition: The computed score equals the WARNING upper threshold exactly.
Steps:
1. `0.50 >= 0.50` is true — Normal classification applies.
2. No alert is emitted.
3. `{:ok, 0.5, :normal}` is returned.

## Failure Flows
### F1: State tracking entry missing after EntropyTracker restart
Condition: The GenServer restarted, losing prior severity state from ETS.
Steps:
1. `record_and_score/2` finds no prior severity entry for the session.
2. It treats the prior state as Normal (safe default).
3. No recovery topology broadcast is emitted.
Result: A brief visual inconsistency is possible (red node not cleared until next LOOP alert cycle), but no crash occurs.

## Gherkin Scenarios

### S1: Score of 0.8 returns normal severity with no alert broadcast
```gherkin
Scenario: High entropy score returns normal classification with no alert
  Given session "sess-healthy" has a sliding window producing a uniqueness ratio of 0.8
  And the entropy_warning_threshold config is 0.50
  When record_and_score/2 is called for session "sess-healthy"
  Then no message is broadcast to "gateway:entropy_alerts"
  And record_and_score/2 returns {:ok, 0.8, :normal}
```

### S2: Session recovering from LOOP broadcasts topology reset
```gherkin
Scenario: Score recovers above 0.50 after prior LOOP state and resets node topology
  Given session "sess-recovering" was previously classified as LOOP with state "alert_entropy" in the topology
  When record_and_score/2 is called and computes a score of 0.6
  Then a topology update with state "active" is broadcast to "gateway:topology"
  And record_and_score/2 returns {:ok, 0.6, :normal}
  And no EntropyAlertEvent is broadcast to "gateway:entropy_alerts"
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that seeds a session window with 5 distinct tuples (score `1.0`) and asserts `record_and_score/2` returns `{:ok, 1.0, :normal}` with no broadcast to `"gateway:entropy_alerts"`.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that first drives a session into LOOP state (score < 0.25) and then adds distinct tuples to bring the score to `0.6`, asserting that `record_and_score/2` returns `{:ok, 0.6, :normal}` and a topology broadcast with `state: "active"` is emitted to `"gateway:topology"`.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** Session sliding window with uniqueness ratio >= 0.50; prior severity state from ETS.
**Outputs:** `{:ok, score, :normal}` return value; optional topology reset broadcast on recovery.
**State changes:** Prior severity state cleared in ETS; topology node state reset to `:active` on recovery.

## Traceability
- Parent FR: FR-9.6
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md)
