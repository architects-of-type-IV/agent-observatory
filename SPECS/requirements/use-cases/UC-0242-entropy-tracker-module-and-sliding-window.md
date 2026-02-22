---
id: UC-0242
title: Record a Tuple into the Session Sliding Window and Return Entropy Score
status: draft
parent_fr: FR-9.1
adrs: [ADR-018, ADR-015]
---

# UC-0242: Record a Tuple into the Session Sliding Window and Return Entropy Score

## Intent
`EntropyTracker.record_and_score/2` is the sole write path for per-session entropy state. It appends a `{intent, tool_call, action_status}` tuple to the session's sliding window, evicts the oldest entry when the window exceeds its configured maximum size, and returns the computed score synchronously. The ETS table is private to the `EntropyTracker` GenServer so that no other module can write entropy tuples directly.

## Primary Actor
EntropyTracker

## Supporting Actors
- ETS table (private, owned by EntropyTracker GenServer process)
- SchemaInterceptor (caller)

## Preconditions
- `EntropyTracker` GenServer is running.
- `SchemaInterceptor` has validated the DecisionLog message before calling `record_and_score/2`.

## Trigger
`EntropyTracker.record_and_score(session_id, {intent, tool_call, action_status})` is called by `SchemaInterceptor` after successful schema validation of a DecisionLog message.

## Main Success Flow
1. `SchemaInterceptor` calls `EntropyTracker.record_and_score("sess-abc", {"plan", "write_file", :success})`.
2. `EntropyTracker` retrieves the current sliding window for "sess-abc" from the private ETS table.
3. If the window is at maximum capacity (5 by default), the oldest tuple is evicted from the head.
4. The new tuple is appended to the window.
5. The uniqueness ratio is computed synchronously: `unique_count / window_size` rounded to 4 decimal places.
6. The severity classification is determined based on the score and current config thresholds.
7. `{:ok, score, severity}` is returned to `SchemaInterceptor`.

## Alternate Flows
### A1: Session window has fewer than max entries
Condition: The session has received fewer than 5 tuples so far (the window is not yet full).
Steps:
1. The new tuple is appended without eviction.
2. The uniqueness ratio is computed over the N available tuples (N < 5).
3. The score and severity are returned normally.

### A2: First tuple for a new session
Condition: No window exists yet for the session_id.
Steps:
1. `EntropyTracker` creates a new window entry in ETS for this session.
2. The single tuple is appended.
3. Score is `1.0` (unique_count = 1, window_size = 1); severity is `:normal`.

## Failure Flows
### F1: Caller bypasses EntropyTracker and writes directly to ETS
Condition: A module other than `SchemaInterceptor` attempts to write to the EntropyTracker's ETS table.
Steps:
1. The ETS table is declared with access `:private` and the owning pid is the EntropyTracker GenServer.
2. The write attempt by the foreign process raises an `:badarg` error (OTP ETS access violation).
Result: The foreign write is prevented by OTP; entropy state is not corrupted.

## Gherkin Scenarios

### S1: Sixth tuple evicts oldest and recomputes score
```gherkin
Scenario: Sixth tuple added to a full window evicts the oldest entry
  Given session "sess-abc" has 5 tuples in its sliding window
  And the oldest tuple is {:search, "list_files", :failure}
  When EntropyTracker.record_and_score("sess-abc", {:plan, "write_file", :success}) is called
  Then the oldest tuple is evicted from the window
  And the new tuple is appended
  And the window still contains exactly 5 tuples
  And the uniqueness ratio is computed over the new 5-tuple window
  And the function returns {:ok, score, severity}
```

### S2: Window with fewer than 5 entries computes score over available entries
```gherkin
Scenario: Partial window computes score over N available tuples
  Given session "sess-new" has 3 tuples in its sliding window
  When EntropyTracker.record_and_score("sess-new", {:search, "grep", :success}) is called
  Then the new tuple is appended making the window size 4
  And the score is computed as unique_count divided by 4
  And the function returns {:ok, score, severity}
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that adds 6 tuples sequentially to the same session and asserts the window never exceeds 5 entries and the oldest is evicted on each overflow.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that adds 3 tuples to a session and asserts the score is computed as `unique_count / 3` rather than `unique_count / 5`.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `session_id` (string), `{intent, tool_call, action_status}` tuple.
**Outputs:** `{:ok, score, severity}` where `score` is a float rounded to 4 decimal places and `severity` is `:normal`, `:warning`, or `:loop`.
**State changes:** ETS window for the session updated with new tuple; oldest evicted if window was full.

## Traceability
- Parent FR: FR-9.1, FR-9.2
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md), [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
