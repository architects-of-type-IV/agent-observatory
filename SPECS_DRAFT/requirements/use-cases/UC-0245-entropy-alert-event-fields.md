---
id: UC-0245
title: Construct and Broadcast a Complete EntropyAlertEvent
status: draft
parent_fr: FR-9.7
adrs: [ADR-018]
---

# UC-0245: Construct and Broadcast a Complete EntropyAlertEvent

## Intent
Every `EntropyAlertEvent` broadcast to `"gateway:entropy_alerts"` must contain all seven required fields — `event_type`, `session_id`, `agent_id`, `entropy_score`, `window_size`, `repeated_pattern`, and `occurrence_count`. If `agent_id` cannot be determined for the session, the event must not be published and `record_and_score/2` must return `{:error, :missing_agent_id}` so the caller can handle the failure cleanly.

## Primary Actor
EntropyTracker

## Supporting Actors
- Phoenix PubSub (topic `"gateway:entropy_alerts"`)
- Session state (source of `agent_id`)

## Preconditions
- `EntropyTracker` GenServer is running.
- LOOP severity has been determined (score < LOOP threshold).
- The session's sliding window contains at least one tuple.

## Trigger
`record_and_score/2` determines LOOP severity and attempts to construct and broadcast an `EntropyAlertEvent`.

## Main Success Flow
1. Score is below LOOP threshold; `EntropyTracker` prepares the `EntropyAlertEvent`.
2. `EntropyTracker` reads `session_id` and `agent_id` for the session (agent_id sourced from a previously received DecisionLog message for this session).
3. `EntropyTracker` identifies the most frequently occurring tuple in the window: `{:search, "list_files", :failure}` appears 4 times.
4. `EntropyTracker` constructs the event map:
   ```
   %{
     event_type: "entropy_alert",
     session_id: "sess-abc",
     agent_id: "agent-7",
     entropy_score: 0.2,
     window_size: 5,
     repeated_pattern: %{intent: "search", tool_call: "list_files", action_status: "failure"},
     occurrence_count: 4
   }
   ```
5. All seven fields are present; the event is broadcast to `"gateway:entropy_alerts"`.
6. `record_and_score/2` continues to return `{:ok, 0.2, :loop}`.

## Alternate Flows
### A1: Window has fewer than 5 tuples
Condition: The window contains 3 tuples because fewer than 5 messages have been received for this session.
Steps:
1. `window_size` in the event is set to `3` (actual window size, not the max capacity of 5).
2. All other fields are populated normally.
3. Event is broadcast.

## Failure Flows
### F1: agent_id cannot be determined for the session
Condition: No DecisionLog message carrying `agent_id` has been received for this session, so `EntropyTracker` cannot populate the required field.
Steps:
1. `EntropyTracker` detects the missing `agent_id`.
2. A warning is logged: `Logger.warning("EntropyTracker: cannot emit alert, missing agent_id for session #{session_id}")`.
3. The event is NOT broadcast to `"gateway:entropy_alerts"`.
4. `record_and_score/2` returns `{:error, :missing_agent_id}` to the caller.
Result: `"gateway:entropy_alerts"` receives no partial event; the incomplete data is not published.

## Gherkin Scenarios

### S1: Complete EntropyAlertEvent broadcast with repeated_pattern and occurrence_count
```gherkin
Scenario: EntropyAlertEvent is broadcast with all seven required fields
  Given session "sess-abc" with agent_id "agent-7" is in LOOP severity
  And the window contains 5 tuples with 4 occurrences of {:search, "list_files", :failure}
  When EntropyTracker prepares the EntropyAlertEvent
  Then the event map contains event_type "entropy_alert"
  And session_id "sess-abc", agent_id "agent-7", entropy_score 0.2, window_size 5
  And repeated_pattern %{intent: "search", tool_call: "list_files", action_status: "failure"}
  And occurrence_count 4
  And the event is broadcast to "gateway:entropy_alerts"
```

### S2: Missing agent_id prevents event broadcast
```gherkin
Scenario: EntropyAlertEvent is not broadcast when agent_id is unavailable
  Given session "sess-noagent" has no known agent_id
  And LOOP severity is detected for the session
  When EntropyTracker attempts to construct the EntropyAlertEvent
  Then no event is broadcast to "gateway:entropy_alerts"
  And a warning is logged referencing the missing agent_id
  And record_and_score/2 returns {:error, :missing_agent_id}
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that triggers LOOP severity for a known session and asserts the `EntropyAlertEvent` broadcast to `"gateway:entropy_alerts"` contains all seven required fields with correct values including `repeated_pattern` and `occurrence_count`.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test where LOOP severity is triggered for a session with no known `agent_id` and asserts no message is broadcast to `"gateway:entropy_alerts"` and `{:error, :missing_agent_id}` is returned.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Current window tuples; `session_id`; `agent_id` (if known); computed score; LOOP threshold.
**Outputs:** `EntropyAlertEvent` map broadcast to `"gateway:entropy_alerts"` (or `{:error, :missing_agent_id}` if `agent_id` unavailable).
**State changes:** PubSub subscribers receive the alert event; EntropyTracker internal state unchanged.

## Traceability
- Parent FR: FR-9.7
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md)
