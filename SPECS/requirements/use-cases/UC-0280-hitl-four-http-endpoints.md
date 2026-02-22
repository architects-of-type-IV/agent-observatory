---
id: UC-0280
title: Expose Four HITL HTTP Endpoints for Session Intervention
status: draft
parent_fr: FR-11.5
adrs: [ADR-021]
---

# UC-0280: Expose Four HITL HTTP Endpoints for Session Intervention

## Intent
This use case covers the four HTTP endpoints that operators use to issue HITL intervention commands against a specific session. All four endpoints are scoped under `/gateway/sessions/:session_id/`, protected by the operator authentication plug, and return HTTP 200 `{"status": "ok"}` on success. The `:session_id` path parameter is extracted from the URL and forwarded to `HITLRelay` as part of the command payload.

## Primary Actor
`ObservatoryWeb.HITLController`

## Supporting Actors
- Phoenix Router (defines all four routes within an authenticated pipeline)
- Operator authentication plug (FR-11.6, enforces `X-Observatory-Operator-Id` header)
- `Observatory.Gateway.HITLRelay` (executes the command and transitions session state)

## Preconditions
- The Phoenix router defines all four routes under a pipeline that includes the operator auth plug.
- `Observatory.Gateway.HITLRelay` is running.
- The request includes a valid `X-Observatory-Operator-Id` header.

## Trigger
An operator tool sends an HTTP POST to one of the four HITL endpoints for a target session.

## Main Success Flow
1. An operator sends `POST /gateway/sessions/sess-abc/pause` with a valid JSON body and a valid `X-Observatory-Operator-Id: operator-xander` header.
2. The operator auth plug validates the header and sets `conn.assigns[:operator_id] = "operator-xander"`.
3. The Phoenix router dispatches to `HITLController`.
4. The controller extracts `session_id` from the path params and `operator_id` from `conn.assigns`.
5. The controller calls `HITLRelay.pause("sess-abc", operator_id: "operator-xander")`.
6. `HITLRelay` transitions the session to `Paused` state and broadcasts `HITLGateOpenEvent`.
7. The controller responds with HTTP 200 and `{"status": "ok"}`.

## Alternate Flows
### A1: Operator issues hitl_unpause to resume a paused session
Condition: The session is in `Paused` state and the operator sends `POST /gateway/sessions/sess-abc/unpause`.
Steps:
1. The auth plug validates the header.
2. The controller calls `HITLRelay.unpause("sess-abc", operator_id: "operator-xander")`.
3. `HITLRelay` transitions to `Normal` and broadcasts `HITLGateCloseEvent`.
4. The controller responds HTTP 200.

## Failure Flows
### F1: Missing X-Observatory-Operator-Id header results in 401
Condition: The request arrives without the `X-Observatory-Operator-Id` header.
Steps:
1. The operator auth plug detects the missing header.
2. The plug halts the connection and responds with HTTP 401 `{"status": "error", "reason": "missing_operator_id"}`.
3. `HITLController` and `HITLRelay` are never called.

## Gherkin Scenarios

### S1: POST /pause with valid operator header returns HTTP 200 and transitions session
```gherkin
Scenario: operator pauses a session via POST /gateway/sessions/:session_id/pause
  Given HITLRelay is running and session "sess-abc" is in Normal state
  And the request includes header X-Observatory-Operator-Id: operator-xander
  When the operator sends POST /gateway/sessions/sess-abc/pause with a valid JSON body
  Then the HTTP response status is 200
  And the response body is {"status": "ok"}
  And HITLRelay transitions "sess-abc" to Paused state
```

### S2: Missing operator header returns HTTP 401 before reaching the controller
```gherkin
Scenario: request without X-Observatory-Operator-Id header is rejected with 401
  Given the operator auth plug is active on the HITL routes
  When a request arrives at POST /gateway/sessions/sess-abc/pause without the header
  Then the HTTP response status is 401
  And the response body contains {"status": "error", "reason": "missing_operator_id"}
  And HITLRelay is never called
```

### S3: All four endpoints are reachable and route to the correct HITLRelay commands
```gherkin
Scenario: all four HITL endpoints are defined and dispatch to the correct commands
  Given the Phoenix router is configured with the four HITL routes
  When POST requests are made to /pause, /unpause, /rewrite, and /inject for a session
  Then each endpoint returns HTTP 200 with {"status": "ok"} for a valid request with the operator header
  And each endpoint routes to the corresponding HITLRelay function: pause, unpause, rewrite, inject
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/controllers/hitl_controller_test.exs` passes a test that sends POST /gateway/sessions/sess-abc/pause with a valid operator header and asserts HTTP 200 with body `{"status": "ok"}`.
- [ ] `mix test test/observatory_web/controllers/hitl_controller_test.exs` passes a test that sends POST /gateway/sessions/sess-abc/pause without the `X-Observatory-Operator-Id` header and asserts HTTP 401.
- [ ] `mix test test/observatory_web/controllers/hitl_controller_test.exs` passes tests for all four endpoints (/pause, /unpause, /rewrite, /inject) confirming each returns HTTP 200 with a valid operator header.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `session_id` path parameter; optional JSON body; `X-Observatory-Operator-Id` header.
**Outputs:** HTTP 200 `{"status": "ok"}` on success; HTTP 401 on missing/blank operator header.
**State changes:** `HITLRelay` session state transitions; `HITLGateOpenEvent` or `HITLGateCloseEvent` broadcast on `"session:hitl:#{session_id}"`; `HITLInterventionEvent` audit row created.

## Traceability
- Parent FR: FR-11.5
- ADR: [ADR-021](../../decisions/ADR-021-hitl-intervention-api.md)
