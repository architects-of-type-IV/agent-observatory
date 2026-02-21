---
id: UC-0248
title: Apply Runtime Configuration Changes to Entropy Thresholds and Window Size
status: draft
parent_fr: FR-9.11
adrs: [ADR-018]
---

# UC-0248: Apply Runtime Configuration Changes to Entropy Thresholds and Window Size

## Intent
`EntropyTracker` must read the LOOP threshold, WARNING threshold, and window size from `Application.get_env/3` on every call to `record_and_score/2`, not at startup. This ensures that threshold changes applied via `Application.put_env/3` — such as those set in tests or a runtime config UI — take effect immediately on the next processed message without requiring an `EntropyTracker` process restart. When an invalid configuration value is present, `EntropyTracker` must fall back to the documented default and continue processing.

## Primary Actor
EntropyTracker

## Supporting Actors
- OTP Application config (`:observatory` namespace)
- SchemaInterceptor (caller of `record_and_score/2`)

## Preconditions
- `EntropyTracker` GenServer is running.
- `Application.put_env/3` has been called to modify one or more of the three config keys before the next `record_and_score/2` call.

## Trigger
`EntropyTracker.record_and_score/2` is called after a runtime configuration change to `:entropy_loop_threshold`, `:entropy_warning_threshold`, or `:entropy_window_size`.

## Main Success Flow
1. A test (or runtime config UI) calls `Application.put_env(:observatory, :entropy_loop_threshold, 0.30)`.
2. `record_and_score/2` is called for the session.
3. Inside `record_and_score/2`, `Application.get_env(:observatory, :entropy_loop_threshold, 0.25)` returns `0.30`.
4. The score `0.28` is evaluated against `0.30`; `0.28 < 0.30` is true — LOOP severity is triggered.
5. Under the default threshold of `0.25`, a score of `0.28` would have been classified as WARNING; the runtime change causes it to be LOOP.
6. `EntropyAlertEvent` is broadcast and `{:ok, 0.28, :loop}` is returned.

## Alternate Flows
### A1: Window size changed at runtime
Condition: `Application.put_env(:observatory, :entropy_window_size, 3)` is called before the next message.
Steps:
1. `record_and_score/2` reads `entropy_window_size` as `3` from `Application.get_env`.
2. Window capacity is treated as 3 for this call; if the current window holds more than 3 tuples, entries beyond 3 are evicted from the head.
3. Score is computed over the capped window.

## Failure Flows
### F1: Invalid threshold type set via Application.put_env
Condition: `Application.put_env(:observatory, :entropy_loop_threshold, "high")` is called; the value is a string rather than a float.
Steps:
1. `record_and_score/2` reads `"high"` from `Application.get_env`.
2. `EntropyTracker` detects that the value is not a number.
3. A warning is logged: `Logger.warning("EntropyTracker: invalid entropy_loop_threshold value 'high', using default 0.25")`.
4. The default value `0.25` is used for this call.
5. Processing continues normally; no crash occurs.
Result: `record_and_score/2` completes with the default threshold; the logged warning allows the operator to correct the misconfiguration.

## Gherkin Scenarios

### S1: Runtime threshold change takes effect on next record_and_score call
```gherkin
Scenario: Increased LOOP threshold reclassifies a previously WARNING score as LOOP
  Given Application.put_env(:observatory, :entropy_loop_threshold, 0.30) has been called
  And a session window produces a uniqueness ratio of 0.28
  When EntropyTracker.record_and_score/2 is called
  Then Application.get_env reads entropy_loop_threshold as 0.30
  And 0.28 is classified as LOOP severity
  And an EntropyAlertEvent is broadcast
  And the function returns {:ok, 0.28, :loop}
```

### S2: Invalid threshold value falls back to default
```gherkin
Scenario: Non-numeric threshold falls back to default without crashing
  Given Application.put_env(:observatory, :entropy_loop_threshold, "high") has been called
  And a session window produces a uniqueness ratio of 0.20
  When EntropyTracker.record_and_score/2 is called
  Then a warning is logged about the invalid threshold value
  And the default threshold 0.25 is used for the evaluation
  And 0.20 is classified as LOOP severity using the default
  And record_and_score/2 returns {:ok, 0.20, :loop} without crashing
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that sets `Application.put_env(:observatory, :entropy_loop_threshold, 0.30)`, then calls `record_and_score/2` with a score that would be WARNING at `0.25` but LOOP at `0.30`, and asserts `{:ok, score, :loop}` is returned.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that sets an invalid string value for `entropy_loop_threshold`, calls `record_and_score/2`, and asserts the default `0.25` is used, a warning is logged, and the process does not crash.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `Application.get_env` values for `:entropy_loop_threshold`, `:entropy_warning_threshold`, `:entropy_window_size` read on each `record_and_score/2` call.
**Outputs:** Severity classification using current runtime config values; warning log on invalid config; fallback to defaults.
**State changes:** None to EntropyTracker internal state from config reads; threshold and window size are ephemeral per-call reads.

## Traceability
- Parent FR: FR-9.11
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md)
