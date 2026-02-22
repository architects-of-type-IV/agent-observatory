---
id: UC-0247
title: Display Entropy Alerts and Issue Pause-and-Inspect Command
status: draft
parent_fr: FR-9.10
adrs: [ADR-018, ADR-021]
---

# UC-0247: Display Entropy Alerts and Issue Pause-and-Inspect Command

## Intent
The Session Cluster Manager LiveView must subscribe to `"gateway:entropy_alerts"` at mount time and render each affected session in an Entropy Alerts panel with a "Pause and Inspect" button. Duplicate alerts for the same session within the panel must be deduplicated by `session_id`. Clicking "Pause and Inspect" must dispatch a Pause command to the HITL API for the affected session. No other UI component may subscribe to `"gateway:entropy_alerts"` in Phase 1.

## Primary Actor
Session Cluster Manager LiveView

## Supporting Actors
- Phoenix PubSub (topic `"gateway:entropy_alerts"`)
- EntropyTracker (source of alert events)
- HITL API (ADR-021, target of Pause command)

## Preconditions
- Session Cluster Manager LiveView is mounted and has subscribed to `"gateway:entropy_alerts"` in `mount/3`.
- The HITL API is reachable for issuing Pause commands.

## Trigger
An `EntropyAlertEvent` is broadcast to `"gateway:entropy_alerts"` by `EntropyTracker`.

## Main Success Flow
1. `EntropyAlertEvent` is broadcast with `session_id: "sess-xyz"`.
2. Session Cluster Manager LiveView receives the event via its PubSub subscription.
3. The LiveView adds "sess-xyz" to the Entropy Alerts panel, displaying the session's `session_id`, `entropy_score`, and `repeated_pattern`.
4. A "Pause and Inspect" button is rendered for "sess-xyz".
5. The operator clicks "Pause and Inspect" for "sess-xyz".
6. The LiveView issues a Pause HITL command to the HITL API for `session_id: "sess-xyz"`.
7. The session is paused pending operator review.

## Alternate Flows
### A1: Duplicate alert for the same session
Condition: A second `EntropyAlertEvent` arrives for "sess-xyz" within 5 seconds (e.g., due to continued repetitive behavior).
Steps:
1. Session Cluster Manager checks whether "sess-xyz" is already in the Entropy Alerts panel.
2. The panel already contains "sess-xyz".
3. The duplicate is discarded; "sess-xyz" appears in the panel exactly once.
4. The existing entry may be updated with the latest score if the new alert carries a different value.

## Failure Flows
### F1: HITL API unreachable when operator clicks Pause and Inspect
Condition: The HITL API call fails (timeout or error response).
Steps:
1. The LiveView issues the Pause command and receives an error.
2. The LiveView renders an error notification for the operator indicating the pause command failed.
3. The "Pause and Inspect" button remains active so the operator can retry.
Result: The session is not paused; the operator is informed and can retry or escalate.

## Gherkin Scenarios

### S1: Entropy alert received and Pause and Inspect button rendered
```gherkin
Scenario: EntropyAlertEvent causes session to appear in Entropy Alerts panel
  Given Session Cluster Manager LiveView is mounted and subscribed to "gateway:entropy_alerts"
  When an EntropyAlertEvent is broadcast with session_id "sess-xyz" and entropy_score 0.2
  Then "sess-xyz" appears in the Entropy Alerts panel
  And a "Pause and Inspect" button is rendered for "sess-xyz"
```

### S2: Operator clicks Pause and Inspect — HITL Pause command issued
```gherkin
Scenario: Operator clicks Pause and Inspect and Pause command is sent to HITL API
  Given session "sess-xyz" is displayed in the Entropy Alerts panel
  When the operator clicks the "Pause and Inspect" button for "sess-xyz"
  Then a Pause HITL command is issued to the HITL API for session_id "sess-xyz"
```

### S3: Duplicate alert does not create duplicate panel entry
```gherkin
Scenario: Second EntropyAlertEvent for the same session does not duplicate the panel entry
  Given "sess-xyz" is already displayed in the Entropy Alerts panel
  When a second EntropyAlertEvent arrives with session_id "sess-xyz"
  Then "sess-xyz" appears in the panel exactly once
  And no duplicate row is rendered
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that broadcasts an `EntropyAlertEvent` to `"gateway:entropy_alerts"` and asserts the Session Cluster Manager LiveView renders the session in the Entropy Alerts panel with a "Pause and Inspect" button.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that broadcasts two `EntropyAlertEvent` messages for the same `session_id` and asserts the session appears only once in the panel.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that simulates an operator clicking the "Pause and Inspect" button for a session in the Entropy Alerts panel and asserts that a Pause HITL command is issued to the HITL API for that `session_id`.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `EntropyAlertEvent` map with `session_id`, `entropy_score`, `repeated_pattern`, `occurrence_count`.
**Outputs:** Entropy Alerts panel entry per unique session; "Pause and Inspect" button; HITL Pause command on button click.
**State changes:** LiveView assigns updated with deduplicated alert list; HITL API receives Pause command for affected session.

## Traceability
- Parent FR: FR-9.10
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md), [ADR-021](../../decisions/ADR-021-hitl-intervention-api.md)
