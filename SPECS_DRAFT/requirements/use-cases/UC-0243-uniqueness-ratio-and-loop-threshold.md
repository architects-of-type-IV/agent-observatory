---
id: UC-0243
title: Compute Uniqueness Ratio and Classify LOOP Severity
status: draft
parent_fr: FR-9.3
adrs: [ADR-018]
---

# UC-0243: Compute Uniqueness Ratio and Classify LOOP Severity

## Intent
The entropy score is computed as the ratio of distinct tuples to total tuples in the current window. When this score falls strictly below the runtime-configurable LOOP threshold (default 0.25), `EntropyTracker` must atomically broadcast an `EntropyAlertEvent`, publish a topology state update setting the node to `:alert_entropy`, and return `{:ok, score, :loop}`. A score exactly equal to the threshold is not LOOP severity. Computation is synchronous and completed within the same process call as `record_and_score/2`.

## Primary Actor
EntropyTracker

## Supporting Actors
- Phoenix PubSub (topics `"gateway:entropy_alerts"` and `"gateway:topology"`)
- Application config (`:observatory, :entropy_loop_threshold`)
- SchemaInterceptor (caller receiving the return value)

## Preconditions
- `EntropyTracker` GenServer is running.
- The sliding window for the session contains at least one tuple.
- The LOOP threshold is readable via `Application.get_env(:observatory, :entropy_loop_threshold, 0.25)`.

## Trigger
`record_and_score/2` completes the uniqueness ratio computation and finds the result is strictly less than the LOOP threshold.

## Main Success Flow
1. The window contains 5 tuples, all identical: `{:search, "read_file", :failure}` repeated 5 times.
2. `unique_count` = 1, `window_size` = 5.
3. Score = `1 / 5` = `0.2`, rounded to 4 decimal places = `0.2000`.
4. `Application.get_env(:observatory, :entropy_loop_threshold, 0.25)` returns `0.25`.
5. `0.2 < 0.25` — LOOP severity is triggered.
6. `EntropyTracker` constructs a valid `EntropyAlertEvent` and broadcasts it to `"gateway:entropy_alerts"`.
7. `EntropyTracker` broadcasts a topology update with `state: "alert_entropy"` to `"gateway:topology"` for the affected session's node.
8. `record_and_score/2` returns `{:ok, 0.2, :loop}`.

## Alternate Flows
None defined — the LOOP classification path is deterministic given the score and threshold.

## Failure Flows
### F1: Score exactly equal to LOOP threshold — not LOOP severity
Condition: The computed score is exactly `0.25` (equal to, not strictly less than, the threshold).
Steps:
1. `EntropyTracker` reads the threshold as `0.25`.
2. `0.25 < 0.25` is `false` — LOOP severity is not triggered.
3. No `EntropyAlertEvent` is broadcast to `"gateway:entropy_alerts"`.
4. Severity is evaluated against the WARNING threshold next.
Result: The session is classified as WARNING (see UC-0244) rather than LOOP.

## Gherkin Scenarios

### S1: Score below LOOP threshold triggers alert and topology update
```gherkin
Scenario: Five identical tuples produce score 0.2 and trigger LOOP severity
  Given session "sess-loop" has a window containing 5 identical tuples {:search, "read_file", :failure}
  And the entropy_loop_threshold is configured as 0.25
  When EntropyTracker.record_and_score("sess-loop", {:search, "read_file", :failure}) is called
  Then the score is computed as 0.2
  And an EntropyAlertEvent is broadcast to "gateway:entropy_alerts"
  And a topology update with state "alert_entropy" is broadcast to "gateway:topology"
  And the function returns {:ok, 0.2, :loop}
```

### S2: Score exactly at threshold is not LOOP
```gherkin
Scenario: Score of exactly 0.25 does not trigger LOOP severity
  Given session "sess-thresh" window produces a uniqueness ratio of 0.25
  And the entropy_loop_threshold is configured as 0.25
  When the score is evaluated
  Then no EntropyAlertEvent is broadcast to "gateway:entropy_alerts"
  And the severity is not :loop
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that fills the window with 5 identical tuples, calls `record_and_score/2`, and asserts `{:ok, 0.2, :loop}` is returned along with a broadcast to `"gateway:entropy_alerts"` and a topology update with `state: "alert_entropy"` on `"gateway:topology"`.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test where the computed score is exactly `0.25` and asserts the return value is not `{:ok, 0.25, :loop}` and no `EntropyAlertEvent` is broadcast.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Current window tuples; `entropy_loop_threshold` from application config.
**Outputs:** `{:ok, score, :loop}`; `EntropyAlertEvent` on `"gateway:entropy_alerts"`; topology update on `"gateway:topology"`.
**State changes:** Node state in topology map set to `"alert_entropy"`.

## Traceability
- Parent FR: FR-9.3, FR-9.4
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md)
