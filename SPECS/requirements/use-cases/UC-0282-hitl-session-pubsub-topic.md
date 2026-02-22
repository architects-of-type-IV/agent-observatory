---
id: UC-0282
title: Broadcast HITL State Changes on session:hitl:{session_id} PubSub Topic
status: draft
parent_fr: FR-11.8
adrs: [ADR-021]
---

# UC-0282: Broadcast HITL State Changes on session:hitl:{session_id} PubSub Topic

## Intent
This use case covers the PubSub topic `"session:hitl:#{session_id}"` used by `HITLRelay` to communicate state changes to the Session Drill-down LiveView. When a session transitions from `Normal` to `Paused`, `HITLRelay` broadcasts `%HITLGateOpenEvent{}` on the session-scoped topic. When the session returns to `Normal`, it broadcasts `%HITLGateCloseEvent{}`. The LiveView subscribes at mount time using the full topic string with the specific `session_id`, ensuring it receives only events for the session it is rendering.

## Primary Actor
`Observatory.Gateway.HITLRelay`

## Supporting Actors
- `ObservatoryWeb.SessionDrilldownLive` (subscribes to `"session:hitl:#{session_id}"` in mount/3)
- `Phoenix.PubSub` (transport layer)

## Preconditions
- `HITLRelay` is running.
- The Session Drill-down LiveView subscribes to `"session:hitl:#{session_id}"` in `mount/3` where `session_id` is the session being rendered.
- `Observatory.PubSub` is configured and started.

## Trigger
An operator issues a `hitl_pause` or `hitl_unpause` command via the HITL HTTP endpoints, causing a state transition in `HITLRelay`.

## Main Success Flow
1. An operator issues `POST /gateway/sessions/sess-abc/pause`.
2. `HITLRelay` transitions session "sess-abc" from `Normal` to `Paused`.
3. `HITLRelay` broadcasts `%HITLGateOpenEvent{session_id: "sess-abc", agent_id: "agent-1", operator_id: "operator-xander", reason: "operator_pause", timestamp: ~U[...]}` on `"session:hitl:sess-abc"`.
4. The Session Drill-down LiveView subscribed to `"session:hitl:sess-abc"` receives the event in `handle_info/2`.
5. The LiveView renders the approval gate UI, showing the buffered DecisionLog content and Approve/Rewrite/Reject buttons.
6. When the operator unpauses, `HITLRelay` broadcasts `%HITLGateCloseEvent{}` on the same topic.
7. The LiveView hides the approval gate and resumes normal session rendering.

## Alternate Flows
### A1: No LiveView is subscribed when a broadcast occurs
Condition: The operator issues a pause before any LiveView mounts for the session.
Steps:
1. `HITLRelay` broadcasts on `"session:hitl:sess-abc"`.
2. No subscriber receives the event.
3. No error occurs; PubSub silently delivers to zero subscribers.
4. When a LiveView subsequently mounts and subscribes, it reads current state from `HITLRelay` directly.

## Failure Flows
### F1: LiveView subscribes to wrong topic (without session_id suffix)
Condition: The LiveView calls `Phoenix.PubSub.subscribe(Observatory.PubSub, "session:hitl")` without the session_id.
Steps:
1. The LiveView receives HITL events for all sessions, not just the rendered one.
2. The approval gate may render for unrelated sessions.
Result: This is a programming error prevented by requiring the full topic string `"session:hitl:#{session_id}"` at mount time.

## Gherkin Scenarios

### S1: HITLRelay broadcasts HITLGateOpenEvent on session-scoped topic when session is paused
```gherkin
Scenario: operator pause triggers HITLGateOpenEvent broadcast on session:hitl:sess-abc
  Given the Session Drill-down LiveView is subscribed to "session:hitl:sess-abc"
  When an operator issues POST /gateway/sessions/sess-abc/pause with a valid operator header
  Then HITLRelay broadcasts %HITLGateOpenEvent{session_id: "sess-abc"} on "session:hitl:sess-abc"
  And the LiveView receives the event and renders the approval gate UI
```

### S2: HITLGateCloseEvent is broadcast when session is unpaused
```gherkin
Scenario: operator unpause triggers HITLGateCloseEvent and LiveView hides approval gate
  Given session "sess-abc" is in Paused state
  And the Session Drill-down LiveView is subscribed to "session:hitl:sess-abc"
  When an operator issues POST /gateway/sessions/sess-abc/unpause
  Then HITLRelay broadcasts %HITLGateCloseEvent{session_id: "sess-abc"} on "session:hitl:sess-abc"
  And the LiveView receives the event and hides the approval gate
```

### S3: LiveView subscription uses full topic string including session_id
```gherkin
Scenario: Session Drill-down LiveView subscribes with full scoped topic at mount
  Given the Session Drill-down LiveView is mounting for session "sess-abc"
  When mount/3 is called
  Then Phoenix.PubSub.subscribe is called with topic "session:hitl:sess-abc"
  And the subscription does not use the unscoped topic "session:hitl"
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/hitl_relay_test.exs` passes a test that subscribes to `"session:hitl:sess-abc"`, calls `HITLRelay.pause("sess-abc", ...)`, and asserts the test process receives `%HITLGateOpenEvent{session_id: "sess-abc"}`.
- [ ] `mix test test/observatory/gateway/hitl_relay_test.exs` passes a test that calls `HITLRelay.unpause("sess-abc", ...)` after a pause and asserts the test process receives `%HITLGateCloseEvent{session_id: "sess-abc"}`.
- [ ] `mix test test/observatory_web/live/session_drilldown_live_test.exs` passes a test that mounts the LiveView for a session and asserts it subscribes to `"session:hitl:#{session_id}"` (not `"session:hitl"`) during mount.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `HITLRelay` state transition triggered by a HITL command; `session_id`, `agent_id`, `operator_id`, `reason`, `timestamp` fields for the event struct.
**Outputs:** `%HITLGateOpenEvent{}` or `%HITLGateCloseEvent{}` broadcast on `"session:hitl:#{session_id}"`.
**State changes:** PubSub broadcast; no ETS or database state is modified by the broadcast itself.

## Traceability
- Parent FR: FR-11.8
- ADR: [ADR-021](../../decisions/ADR-021-hitl-intervention-api.md)
