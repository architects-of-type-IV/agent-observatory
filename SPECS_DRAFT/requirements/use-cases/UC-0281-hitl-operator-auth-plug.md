---
id: UC-0281
title: Authenticate HITL Requests via X-Observatory-Operator-Id Header Plug
status: draft
parent_fr: FR-11.6
adrs: [ADR-021]
---

# UC-0281: Authenticate HITL Requests via X-Observatory-Operator-Id Header Plug

## Intent
This use case covers the operator authentication plug that guards all four HITL HTTP endpoints. In Phase 1 the plug validates only that the `X-Observatory-Operator-Id` header is present and non-empty after trimming whitespace. A valid header causes the plug to store the operator identifier in `conn.assigns[:operator_id]` and call `next` in the plug pipeline. A missing or blank header causes the plug to halt the connection with HTTP 401 before the request body is parsed or the controller is invoked.

## Primary Actor
`Observatory.Plugs.OperatorAuth`

## Supporting Actors
- Phoenix Router (includes the plug in the HITL route pipeline)
- `ObservatoryWeb.HITLController` (receives `conn.assigns[:operator_id]` after plug runs)
- `Observatory.Gateway.HITLRelay` (reads `operator_id` from the command payload for audit logging)

## Preconditions
- `Observatory.Plugs.OperatorAuth` is defined in `lib/observatory_web/plugs/operator_auth.ex`.
- The plug is included in the router pipeline used by all four HITL routes.
- No OAuth token validation is required in Phase 1.

## Trigger
An HTTP request arrives at any of the four HITL endpoints.

## Main Success Flow
1. A request arrives at `POST /gateway/sessions/sess-abc/pause` with header `X-Observatory-Operator-Id: operator-xander`.
2. The plug reads the header using `Plug.Conn.get_req_header/2`.
3. The plug applies `String.trim/1` to the header value.
4. The trimmed value is non-empty; the plug sets `conn.assigns[:operator_id] = "operator-xander"`.
5. The plug calls `next` (`Plug.Conn.call/2`), passing control to the next plug in the pipeline.
6. `HITLController` reads `conn.assigns[:operator_id]` and includes it in the `HITLInterventionEvent` audit record.

## Alternate Flows
### A1: Phase 2 OAuth upgrade
Condition: A Phase 2 OAuth integration replaces the header presence check with token validation.
Steps:
1. Only the plug implementation changes; the controller and `HITLRelay` continue to read `conn.assigns[:operator_id]` unchanged.
2. No controller or relay code requires modification.

## Failure Flows
### F1: Missing header results in HTTP 401
Condition: The request arrives without the `X-Observatory-Operator-Id` header.
Steps:
1. `Plug.Conn.get_req_header/2` returns an empty list.
2. The plug calls `Plug.Conn.send_resp(conn, 401, Jason.encode!(%{status: "error", reason: "missing_operator_id"}))` and halts the connection.
3. No downstream plug or controller receives the request.

### F2: Whitespace-only header value is treated as absent
Condition: The request includes header `X-Observatory-Operator-Id:    ` (spaces only).
Steps:
1. The plug calls `String.trim/1` on the header value; the result is an empty string.
2. The plug treats the empty trimmed string as absent and responds with HTTP 401.
Result: Blank or whitespace-only operator IDs are rejected to prevent audit log pollution.

## Gherkin Scenarios

### S1: Valid operator header passes through plug and sets conn.assigns[:operator_id]
```gherkin
Scenario: X-Observatory-Operator-Id header present and non-empty sets operator_id assign
  Given a request to POST /gateway/sessions/sess-abc/pause with header X-Observatory-Operator-Id: operator-xander
  When the OperatorAuth plug processes the connection
  Then conn.assigns[:operator_id] is set to "operator-xander"
  And the plug calls next to continue the pipeline
```

### S2: Missing header halts connection with HTTP 401
```gherkin
Scenario: absent X-Observatory-Operator-Id header returns 401 before controller runs
  Given a request to POST /gateway/sessions/sess-abc/pause with no X-Observatory-Operator-Id header
  When the OperatorAuth plug processes the connection
  Then the connection is halted with HTTP status 401
  And the response body is {"status": "error", "reason": "missing_operator_id"}
  And no downstream controller or plug receives the request
```

### S3: Whitespace-only header value is treated as absent and returns 401
```gherkin
Scenario: X-Observatory-Operator-Id header with only whitespace is rejected as blank
  Given a request with header X-Observatory-Operator-Id set to a string of only spaces
  When the OperatorAuth plug applies String.trim/1 and checks the result
  Then the trimmed value is an empty string
  And the plug responds with HTTP 401 with reason "missing_operator_id"
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/plugs/operator_auth_test.exs` passes a test that provides `X-Observatory-Operator-Id: operator-xander` and asserts `conn.assigns[:operator_id] == "operator-xander"` and the connection is not halted.
- [ ] `mix test test/observatory_web/plugs/operator_auth_test.exs` passes a test that omits the header and asserts the response is HTTP 401 with body containing `"missing_operator_id"`.
- [ ] `mix test test/observatory_web/plugs/operator_auth_test.exs` passes a test that provides a whitespace-only header value and asserts the response is HTTP 401.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `X-Observatory-Operator-Id` request header value (string or absent).
**Outputs:** `conn.assigns[:operator_id]` populated on success; HTTP 401 JSON error on failure.
**State changes:** Read-only; no ETS or database state is modified by the plug itself.

## Traceability
- Parent FR: FR-11.6
- ADR: [ADR-021](../../decisions/ADR-021-hitl-intervention-api.md)
