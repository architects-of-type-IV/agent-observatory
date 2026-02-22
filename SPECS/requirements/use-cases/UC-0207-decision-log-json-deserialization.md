---
id: UC-0207
title: Deserialize JSON Request Body into DecisionLog Changeset
status: draft
parent_fr: FR-6.8
adrs: [ADR-014, ADR-015]
---

# UC-0207: Deserialize JSON Request Body into DecisionLog Changeset

## Intent
This use case covers the HTTP request body parsing step that precedes changeset validation. The Gateway endpoint must decode the incoming JSON body using `Plug.Parsers` with the `:json` parser and the `Jason` library. A well-formed JSON body is decoded into a string-keyed params map and passed to `DecisionLog.changeset/2`. A malformed JSON body (unparseable) must be caught before reaching the changeset layer and must produce HTTP 400. A valid JSON body that fails schema validation produces HTTP 422, not HTTP 400, preserving the semantic distinction between parse errors and validation errors.

## Primary Actor
`ObservatoryWeb.GatewayController`

## Supporting Actors
- `Plug.Parsers` (decodes JSON body into params map)
- `Jason` (JSON parsing library)
- `Observatory.Gateway.SchemaInterceptor` (called after successful JSON parse)
- `Observatory.Mesh.DecisionLog` (changeset target)

## Preconditions
- The Phoenix router places the `POST /gateway/messages` route in a pipeline that includes `Plug.Parsers` configured with `:json` and `Jason`.
- `ObservatoryWeb.GatewayController` defines the `create` action (or equivalent) that handles this route.

## Trigger
An HTTP POST request arrives at `/gateway/messages` with a request body.

## Main Success Flow
1. An agent sends `POST /gateway/messages` with a well-formed JSON body.
2. `Plug.Parsers` decodes the JSON body into a string-keyed params map using `Jason`.
3. The controller receives the params map via `conn.body_params`.
4. The controller calls `SchemaInterceptor.validate(params)`.
5. `DecisionLog.changeset/2` is invoked internally; `Ecto.Changeset.cast/4` handles atom conversion from string keys.
6. `Ecto.Changeset.valid?/1` returns `true`.
7. The controller extracts the struct via `Ecto.Changeset.apply_changes/1` and proceeds.

## Alternate Flows
### A1: Valid JSON body that fails schema validation returns HTTP 422
Condition: The JSON body is syntactically valid but missing required fields.
Steps:
1. `Plug.Parsers` successfully decodes the JSON body.
2. `SchemaInterceptor.validate/1` returns `{:error, changeset}`.
3. The controller responds with HTTP 422 and a structured error body.
4. The HTTP status is 422, not 400.

## Failure Flows
### F1: Malformed JSON body returns HTTP 400
Condition: The request body contains invalid JSON (e.g., missing quotes around a key).
Steps:
1. `Plug.Parsers` raises a `Plug.Parsers.ParseError` during body decoding.
2. The controller or a Plug error handler rescues the exception.
3. The controller responds with HTTP 400 and body `{"status": "error", "reason": "invalid_json"}`.
4. `SchemaInterceptor.validate/1` is never called.
Result: The agent receives HTTP 400 and can distinguish a parse failure from a schema validation failure.

## Gherkin Scenarios

### S1: Well-formed JSON body is decoded and reaches the changeset layer
```gherkin
Scenario: valid JSON body is parsed by Plug.Parsers and passed to DecisionLog.changeset/2
  Given a POST request to /gateway/messages with a well-formed JSON body containing all required fields
  When Plug.Parsers decodes the request body
  Then the controller receives a string-keyed params map
  And SchemaInterceptor.validate/1 is called with the params map
  And the HTTP response status is 202
```

### S2: Malformed JSON body is rejected with HTTP 400 before reaching changeset
```gherkin
Scenario: malformed JSON body triggers HTTP 400 before schema validation
  Given a POST request to /gateway/messages with a request body containing invalid JSON
  When Plug.Parsers raises a ParseError during decoding
  Then the controller responds with HTTP 400
  And the response body is {"status": "error", "reason": "invalid_json"}
  And SchemaInterceptor.validate/1 is not called
```

### S3: Syntactically valid JSON that fails schema validation produces HTTP 422
```gherkin
Scenario: valid JSON with missing required fields produces HTTP 422 not HTTP 400
  Given a POST request to /gateway/messages with valid JSON that omits meta.trace_id
  When Plug.Parsers decodes the body successfully and SchemaInterceptor.validate/1 is called
  Then SchemaInterceptor.validate/1 returns {:error, changeset}
  And the HTTP response status is 422
  And the response status is not 400
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts a well-formed JSON body and asserts the response is HTTP 202 with `trace_id` in the body.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts malformed JSON and asserts the response is HTTP 400 with `reason: "invalid_json"`.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts syntactically valid JSON with a missing required field and asserts the response is HTTP 422 (not 400).
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** HTTP POST request body as raw bytes; may be well-formed JSON, malformed JSON, or valid JSON with schema violations.
**Outputs:** HTTP 202 on full success; HTTP 422 on schema failure; HTTP 400 on parse failure.
**State changes:** On success, a PubSub broadcast on `"gateway:messages"` occurs. On failure, a PubSub broadcast on `"gateway:violations"` occurs. No ETS or database state is modified.

## Traceability
- Parent FR: FR-6.8
- ADR: [ADR-014](../../decisions/ADR-014-decision-log-envelope.md)
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
