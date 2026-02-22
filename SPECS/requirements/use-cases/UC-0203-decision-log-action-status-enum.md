---
id: UC-0203
title: Validate action.status Enum Field
status: draft
parent_fr: FR-6.4
adrs: [ADR-014]
---

# UC-0203: Validate action.status Enum Field

## Intent
This use case covers the enforcement of the `action.status` enum constraint within the `Action` embedded schema. The field must be defined using `Ecto.Enum` restricted to exactly four atoms: `:success`, `:failure`, `:pending`, and `:skipped`. Any value outside this set must cause the changeset to add a validation error. The Gateway rejects the message with HTTP 422 and includes a descriptive `detail` field in the response body when an invalid status value is submitted.

## Primary Actor
`Observatory.Mesh.DecisionLog`

## Supporting Actors
- `Ecto.Enum` (field type for action.status)
- `Observatory.Gateway.SchemaInterceptor` (reads changeset validity to produce HTTP 422)
- `ObservatoryWeb.GatewayController` (formats the 422 response body with the detail string)

## Preconditions
- The `Action` embedded schema defines `field :status, Ecto.Enum, values: [:success, :failure, :pending, :skipped]`.
- `Observatory.Mesh.DecisionLog.changeset/2` is defined and compiles without warnings.

## Trigger
A call to `Observatory.Mesh.DecisionLog.changeset(%DecisionLog{}, params)` where `params["action"]["status"]` is either a valid or invalid enum string.

## Main Success Flow
1. The caller passes a params map with `"action" => %{"status" => "pending"}` alongside all other required fields.
2. Ecto casts the string `"pending"` to the atom `:pending` via `Ecto.Enum`.
3. No validation error is added on `:status`.
4. `Ecto.Changeset.valid?/1` returns `true`.
5. `Ecto.Changeset.apply_changes/1` returns a struct with `action.status: :pending`.
6. The Gateway forwards the struct.

## Alternate Flows
### A1: Valid status values other than :pending
Condition: The params map contains `"status": "success"`, `"status": "failure"`, or `"status": "skipped"`.
Steps:
1. Ecto casts the string to the corresponding atom.
2. No validation error is added.
3. `Ecto.Changeset.valid?/1` returns `true`.

## Failure Flows
### F1: Invalid enum value submitted
Condition: The params map contains `"action" => %{"status" => "timeout"}`.
Steps:
1. `Ecto.Enum` fails to match `"timeout"` to any atom in `[:success, :failure, :pending, :skipped]`.
2. Ecto adds a validation error `{"is invalid", [validation: :inclusion]}` on `:status`.
3. `Ecto.Changeset.valid?/1` returns `false`.
4. The Gateway calls `SchemaInterceptor.validate/1`, which returns `{:error, changeset}`.
5. The controller responds with HTTP 422 and body `{"status": "rejected", "reason": "schema_violation", "detail": "invalid value for action.status: timeout", "trace_id": null}`.
Result: The message is rejected; no PubSub broadcast occurs on `"gateway:messages"`.

## Gherkin Scenarios

### S1: Valid enum value passes validation
```gherkin
Scenario: action.status "pending" casts to :pending and passes changeset validation
  Given a params map with action.status set to "pending" and all other required fields present
  When Observatory.Mesh.DecisionLog.changeset/2 is called with the params map
  Then Ecto.Changeset.valid?/1 returns true
  And apply_changes/1 returns a struct with action.status equal to :pending
```

### S2: Invalid enum value causes validation error and HTTP 422
```gherkin
Scenario: action.status "timeout" produces a validation error and HTTP 422 response
  Given a params map with action.status set to "timeout" and all other required fields present
  When the Gateway receives the request and calls SchemaInterceptor.validate/1
  Then SchemaInterceptor.validate/1 returns {:error, changeset}
  And the changeset errors include status: {"is invalid", [validation: :inclusion]}
  And the HTTP response status is 422
  And the response body detail field contains "invalid value for action.status: timeout"
```

### S3: HTTP endpoint returns 422 with detail mentioning the invalid field
```gherkin
Scenario: POST /gateway/messages with invalid action.status returns 422 with detail field
  Given a syntactically valid JSON payload with action.status set to "timeout"
  When the payload is submitted to POST /gateway/messages
  Then the HTTP response status is 422
  And the response body contains a "detail" field that includes the string "action.status"
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that sets `action.status` to each of the four valid atoms and asserts `Ecto.Changeset.valid?(changeset) == true` for each.
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that sets `action.status` to `"timeout"` and asserts the changeset errors include `{:status, {"is invalid", [validation: :inclusion]}}`.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts a payload with `action.status: "timeout"` and asserts the HTTP response is 422 with a `detail` field containing `"action.status"`.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `params["action"]["status"]` as a string; the four valid values are `"success"`, `"failure"`, `"pending"`, and `"skipped"`.
**Outputs:** `action.status` atom (`:success`, `:failure`, `:pending`, `:skipped`) on success; `{:status, {"is invalid", [validation: :inclusion]}}` changeset error on failure.
**State changes:** Read-only; no state is modified.

## Traceability
- Parent FR: FR-6.4
- ADR: [ADR-014](../../decisions/ADR-014-decision-log-envelope.md)
