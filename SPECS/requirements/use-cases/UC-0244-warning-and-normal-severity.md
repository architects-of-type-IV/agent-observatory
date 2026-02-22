---
id: UC-0244
title: Classify WARNING and Normal Entropy Severity and Recover Node State
status: draft
parent_fr: FR-9.5
adrs: [ADR-018]
---

# UC-0244: Classify WARNING and Normal Entropy Severity and Recover Node State

## Intent
When the entropy score falls between the LOOP and WARNING thresholds (0.25 inclusive to 0.50 exclusive), `EntropyTracker` must classify the session as WARNING, update the node to `:blocked` amber rendering via a topology broadcast, and return `{:ok, score, :warning}` without emitting an `EntropyAlertEvent`. When the score recovers to 0.50 or above (Normal range), no alert or topology change occurs unless the session was previously in WARNING or LOOP, in which case the node state must be reset to reflect the node's actual operational state. Prior WARNING state must never suppress a subsequent LOOP classification.

## Primary Actor
EntropyTracker

## Supporting Actors
- Phoenix PubSub (topics `"gateway:topology"` and, for LOOP escalation, `"gateway:entropy_alerts"`)
- Application config (`:observatory, :entropy_warning_threshold`)
- SchemaInterceptor (caller)

## Preconditions
- `EntropyTracker` GenServer is running.
- The session has an established sliding window.

## Trigger
`record_and_score/2` completes the uniqueness ratio computation and finds the result is within the WARNING band or the Normal band.

## Main Success Flow (WARNING)
1. Score computed as `0.4` (>= 0.25 and < 0.50 — WARNING band).
2. `Application.get_env(:observatory, :entropy_warning_threshold, 0.50)` returns `0.50`.
3. No `EntropyAlertEvent` is broadcast to `"gateway:entropy_alerts"`.
4. A topology update is broadcast to `"gateway:topology"` setting the node's `state` to `"blocked"` (amber `#f59e0b`).
5. `record_and_score/2` returns `{:ok, 0.4, :warning}`.

## Alternate Flows
### A1: Score in Normal range (>= 0.50)
Condition: Score is 0.8 — above both thresholds.
Steps:
1. No `EntropyAlertEvent` is broadcast.
2. If the session was previously in WARNING or LOOP, a topology update is broadcast resetting the node to `:active` (or `:idle` if inactive).
3. `record_and_score/2` returns `{:ok, 0.8, :normal}`.

### A2: Score escalates from WARNING to LOOP
Condition: A subsequent call computes `0.18` after the previous call returned WARNING severity.
Steps:
1. `EntropyTracker` evaluates `0.18 < 0.25` — LOOP threshold breached.
2. Prior WARNING state does not suppress the LOOP classification.
3. `EntropyAlertEvent` is broadcast to `"gateway:entropy_alerts"`.
4. Topology update sets node to `"alert_entropy"`.
5. Returns `{:ok, 0.18, :loop}`.

## Failure Flows
### F1: Score exactly at WARNING upper boundary is classified as Normal
Condition: Score computed as exactly `0.50`.
Steps:
1. `0.50 >= 0.50` — not in WARNING band.
2. Session is classified as Normal; no topology state change broadcast (unless recovering from prior WARNING/LOOP).
3. Returns `{:ok, 0.5, :normal}`.
Result: No WARNING behavior is triggered for a boundary score.

## Gherkin Scenarios

### S1: WARNING score triggers topology blocked state without alert
```gherkin
Scenario: Score in WARNING band sets node to blocked amber without emitting an alert
  Given session "sess-warn" has a computed entropy score of 0.4
  And entropy_warning_threshold is configured as 0.50
  When the severity is evaluated
  Then no EntropyAlertEvent is broadcast to "gateway:entropy_alerts"
  And a topology update is broadcast to "gateway:topology" with state "blocked"
  And record_and_score/2 returns {:ok, 0.4, :warning}
```

### S2: Score recovery to Normal resets node state
```gherkin
Scenario: Score recovering above 0.50 resets node from blocked to active
  Given session "sess-recover" was previously classified as WARNING
  And the current computed score is 0.8
  When the severity is evaluated
  Then no EntropyAlertEvent is broadcast
  And a topology update is broadcast resetting the node state to :active
  And record_and_score/2 returns {:ok, 0.8, :normal}
```

### S3: Prior WARNING does not suppress LOOP escalation
```gherkin
Scenario: Score dropping from WARNING to LOOP triggers LOOP alert despite prior WARNING
  Given session "sess-escalate" was last classified as WARNING with score 0.35
  And the current computed score is 0.18
  When the severity is evaluated
  Then an EntropyAlertEvent is broadcast to "gateway:entropy_alerts"
  And a topology update sets node state to "alert_entropy"
  And record_and_score/2 returns {:ok, 0.18, :loop}
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that produces a WARNING score and asserts no `EntropyAlertEvent` is broadcast and the topology update sets `state: "blocked"`.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that produces a Normal score following a WARNING session and asserts a topology update resetting the node to `:active` is broadcast.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that transitions from WARNING to LOOP and asserts the LOOP `EntropyAlertEvent` is broadcast despite the prior WARNING classification.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Computed score; `entropy_warning_threshold` from config; prior severity state for recovery detection.
**Outputs:** `{:ok, score, :warning}` or `{:ok, score, :normal}`; optional topology broadcast.
**State changes:** Node topology state updated to `"blocked"` on WARNING; reset on Normal recovery.

## Traceability
- Parent FR: FR-9.5, FR-9.6
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md)
