---
id: UC-0250
title: Maintain Per-Session Sliding Window of Entropy Tuples
status: draft
parent_fr: FR-9.2
adrs: [ADR-018]
---

# UC-0250: Maintain Per-Session Sliding Window of Entropy Tuples

## Intent
`EntropyTracker` maintains exactly one sliding window per session, holding the last 5 `{intent, tool_call, action_status}` tuples in insertion order. When a sixth tuple arrives the oldest is evicted so the window never exceeds 5 entries. When fewer than 5 tuples have arrived the uniqueness ratio is computed over the available N entries rather than waiting for a full window. Window state persists in ETS keyed by `session_id` across sequential calls to `record_and_score/2`.

## Primary Actor
`Observatory.Gateway.EntropyTracker`

## Supporting Actors
- ETS table owned by the `EntropyTracker` GenServer (private, keyed by `session_id`)
- `SchemaInterceptor` (caller of `record_and_score/2`)

## Preconditions
- `EntropyTracker` GenServer is running with its private ETS table initialised.
- The session `"sess-abc"` has no prior window entries (first call) or has existing entries (subsequent calls).

## Trigger
`SchemaInterceptor` calls `EntropyTracker.record_and_score("sess-abc", {intent, tool_call, action_status})` after a successful schema validation.

## Main Success Flow
1. `record_and_score/2` receives session `"sess-abc"` and tuple `{"plan", "write_file", :success}`.
2. `EntropyTracker` reads the current window for `"sess-abc"` from ETS.
3. The new tuple is appended to the window.
4. If the window now contains more than 5 tuples, the oldest tuple is evicted.
5. The updated window is written back to ETS under the key `"sess-abc"`.
6. The uniqueness ratio is computed over the current window (up to 5 entries).
7. `{:ok, score, severity}` is returned to the caller.

## Alternate Flows
### A1: Window has fewer than 5 tuples
Condition: Only 3 tuples have been recorded for the session so far.
Steps:
1. The new tuple brings the window to 4 entries (still below 5).
2. No eviction occurs.
3. The uniqueness ratio is computed over 4 tuples: `unique_count / 4`.
4. The score is returned normally.

## Failure Flows
### F1: ETS table missing (EntropyTracker crashed and restarted)
Condition: The EntropyTracker GenServer has restarted, losing the prior ETS table.
Steps:
1. `record_and_score/2` reads the ETS table and finds no entry for `"sess-abc"`.
2. A new empty window is initialised for `"sess-abc"`.
3. The incoming tuple is written as the first entry.
4. Score is computed over a window of 1 (returns `1.0` — single unique entry).
Result: Window accumulation restarts cleanly after a crash; no error is propagated to the caller.

## Gherkin Scenarios

### S1: Sixth tuple evicts oldest and window remains size 5
```gherkin
Scenario: Sixth tuple causes oldest entry to be evicted from the sliding window
  Given session "sess-abc" has 5 tuples recorded in its sliding window
  When a sixth tuple {"execute", "run_shell", :failure} is passed to record_and_score/2
  Then the oldest tuple is evicted from the window
  And the window contains exactly 5 tuples with the sixth tuple as the most recent entry
  And the returned score reflects the uniqueness ratio over the 5-entry window
```

### S2: Score computed over partial window when fewer than 5 tuples present
```gherkin
Scenario: Entropy score is computed over available entries when window is not yet full
  Given session "sess-new" has no prior window entries
  When three sequential calls to record_and_score/2 are made with distinct tuples
  Then the third call returns a score computed as unique_count divided by 3
  And no error is returned due to the partial window size
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that calls `record_and_score/2` six times for the same session with distinct tuples and asserts that after the sixth call the internal window contains exactly 5 entries and the oldest tuple is no longer present.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that calls `record_and_score/2` three times with three distinct tuples on a fresh session and asserts the returned score equals `1.0` (3 unique out of 3 total) computed over the partial window.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `session_id` (string), `{intent, tool_call, action_status}` tuple.
**Outputs:** `{:ok, score, severity}` where score is the uniqueness ratio rounded to 4 decimal places.
**State changes:** ETS entry for `session_id` updated with the new window (evicting oldest entry when window exceeds 5).

## Traceability
- Parent FR: FR-9.2
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md)
