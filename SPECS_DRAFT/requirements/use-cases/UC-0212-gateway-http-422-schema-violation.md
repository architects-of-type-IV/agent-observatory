---
id: UC-0212
title: Return HTTP 422 with Structured Error Body on Schema Violation
status: draft
parent_fr: FR-7.4
adrs: [ADR-015]
---

# UC-0212: Return HTTP 422 with Structured Error Body on Schema Violation

## Intent
This use case covers the HTTP 422 response that the Gateway controller must produce when `SchemaInterceptor.validate/1` returns `{:error, changeset}`. The response body must conform to a specific JSON structure with `status`, `reason`, `detail`, and `trace_id` fields. The `detail` field is derived from the changeset errors using `Ecto.Changeset.traverse_errors/2`. The `trace_id` field is always `null` in the 422 case because the message was rejected before a valid `meta.trace_id` was confirmed. The response must carry `Content-Type: application/json`. HTTP 422 is distinct from HTTP 400, which is reserved for malformed JSON.

## Primary Actor
`ObservatoryWeb.GatewayController`

## Supporting Actors
- `Observatory.Gateway.SchemaInterceptor` (returns `{:error, changeset}`)
- `Ecto.Changeset` (traverse_errors/2 derives the detail string)

## Preconditions
- The controller has received `{:error, changeset}` from `SchemaInterceptor.validate/1`.
- `Ecto.Changeset.traverse_errors/2` or an equivalent error formatting function is available.
- The response pipeline sets `Content-Type: application/json`.

## Trigger
`SchemaInterceptor.validate/1` returns `{:error, changeset}` and the controller proceeds to build the rejection response.

## Main Success Flow
1. The controller pattern-matches `{:error, changeset}` from `SchemaInterceptor.validate/1`.
2. The controller calls `Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} -> Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end) end)` or an equivalent helper.
3. The controller formats the first validation error into a human-readable string for the `detail` field (e.g., `"agent_id: can't be blank"`).
4. The controller calls `json_response(conn, 422)` with the body `%{"status" => "rejected", "reason" => "schema_violation", "detail" => detail_string, "trace_id" => nil}`.
5. The response carries HTTP status 422 and `Content-Type: application/json`.

## Alternate Flows
### A1: Multiple validation errors in changeset
Condition: The changeset contains errors on more than one field.
Steps:
1. The controller traverses all errors but includes only the first error in the `detail` field.
2. The response body is otherwise unchanged.
3. The agent receives a single actionable detail string; they must fix and resubmit to discover subsequent errors.

## Failure Flows
### F1: Controller returns HTTP 400 for a schema validation failure
Condition: A developer incorrectly uses a 400 status code for a schema validation failure.
Steps:
1. The agent receives HTTP 400 and interprets the failure as a JSON parse error.
2. The agent retries with the same well-formed JSON payload, receiving 400 again.
3. The agent cannot distinguish the parse error from the semantic error.
Result: This failure is prevented by the explicit status code requirement in FR-7.4 and by the integration test that asserts 422, not 400.

## Gherkin Scenarios

### S1: Missing agent_id produces HTTP 422 with structured body
```gherkin
Scenario: missing identity.agent_id causes HTTP 422 with schema_violation detail
  Given a POST request to /gateway/messages with a valid JSON body that omits identity.agent_id
  When SchemaInterceptor.validate/1 returns {:error, changeset}
  Then the HTTP response status is 422
  And the response Content-Type is application/json
  And the response body is {"status": "rejected", "reason": "schema_violation", "detail": "agent_id: can't be blank", "trace_id": null}
```

### S2: Schema failure response status is 422 not 400
```gherkin
Scenario: well-formed JSON with missing required field produces 422 not 400
  Given a POST request with syntactically valid JSON missing meta.trace_id
  When the controller processes the request
  Then the HTTP response status is 422
  And the response status is not 400
  And the response body reason field is "schema_violation"
```

### S3: trace_id field in 422 response body is null for schema violations
```gherkin
Scenario: 422 schema violation response includes trace_id: null in the response body
  Given a POST request to /gateway/messages with a payload missing identity.agent_id
  When the controller renders the 422 response body
  Then the response body contains a "trace_id" key
  And the value of "trace_id" is null
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts a payload missing `identity.agent_id` and asserts the response is HTTP 422 with body containing `"status": "rejected"`, `"reason": "schema_violation"`, and a `"detail"` string mentioning `"agent_id"`.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that asserts the `"trace_id"` field in the 422 response is `null`.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts syntactically valid JSON missing `meta.trace_id` and asserts the response is HTTP 422, not HTTP 400.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `{:error, %Ecto.Changeset{}}` from `SchemaInterceptor.validate/1`; changeset errors map.
**Outputs:** HTTP 422 response with JSON body `{"status": "rejected", "reason": "schema_violation", "detail": "<string>", "trace_id": null}`.
**State changes:** A `SchemaViolationEvent` is broadcast on `"gateway:violations"` (covered in UC-0215). The HTTP response itself does not modify ETS or database state.

## Traceability
- Parent FR: FR-7.4
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
