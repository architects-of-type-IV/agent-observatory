---
id: UC-0211
title: Accept Agent Messages via POST /gateway/messages
status: draft
parent_fr: FR-7.3
adrs: [ADR-013, ADR-015]
---

# UC-0211: Accept Agent Messages via POST /gateway/messages

## Intent
This use case covers the HTTP endpoint that agents use to submit DecisionLog messages to the Observatory. The endpoint is a POST route at `/gateway/messages`, handled by `ObservatoryWeb.GatewayController`. The route is placed in a pipeline that includes JSON body parsing. No session authentication is required in Phase 1. The controller calls `SchemaInterceptor.validate/1` as its first action after decoding the body. An agent that sends a request to the wrong path (e.g., `/gateway/message` with no trailing `s`) receives HTTP 404 from the Phoenix router and the controller is never invoked.

## Primary Actor
`ObservatoryWeb.GatewayController`

## Supporting Actors
- Phoenix Router (defines the route and pipeline)
- `Plug.Parsers` (JSON body parsing)
- `Observatory.Gateway.SchemaInterceptor` (first action after body decode)
- `Jason` (JSON parsing library)

## Preconditions
- The Phoenix router defines `post "/gateway/messages", GatewayController, :create` (or equivalent action name).
- The route is in a pipeline that includes `plug Plug.Parsers, parsers: [:json], json_decoder: Jason`.
- The route does not require `plug :put_secure_browser_headers` or session authentication plugs.
- `ObservatoryWeb.GatewayController` defines the handler action.

## Trigger
An external agent sends an HTTP POST request to `/gateway/messages`.

## Main Success Flow
1. An agent sends `POST /gateway/messages` with a valid JSON body and `Content-Type: application/json`.
2. The Phoenix router matches the route and dispatches to `GatewayController`.
3. `Plug.Parsers` decodes the JSON body using `Jason` and populates `conn.body_params`.
4. The controller calls `SchemaInterceptor.validate(conn.body_params)` as its first action.
5. `SchemaInterceptor.validate/1` returns `{:ok, log}`.
6. The controller completes processing (entropy overwrite, PubSub broadcast).
7. The controller responds with HTTP 202 and `{"status": "accepted", "trace_id": "<log.meta.trace_id>"}`.

## Alternate Flows
### A1: Agent uses the wrong path
Condition: The agent sends `POST /gateway/message` (singular).
Steps:
1. The Phoenix router does not match any route for `/gateway/message`.
2. The router responds with HTTP 404.
3. `GatewayController` is never invoked and `SchemaInterceptor.validate/1` is never called.

## Failure Flows
### F1: Request without Content-Type: application/json
Condition: The agent omits the `Content-Type` header or sends a non-JSON content type.
Steps:
1. `Plug.Parsers` may not decode the body as JSON or may return an empty params map.
2. `SchemaInterceptor.validate/1` receives an empty map.
3. All required fields are missing; `valid?/1` returns `false`.
4. The controller responds with HTTP 422 describing the missing required fields.
Result: The agent receives a schema validation error, not a parse error, because the body was not decoded as JSON (empty map is valid JSON from the parser's perspective).

## Gherkin Scenarios

### S1: Valid JSON POST to correct path returns HTTP 202
```gherkin
Scenario: agent sends valid POST to /gateway/messages and receives HTTP 202
  Given an agent with a valid DecisionLog JSON payload
  When the agent sends POST /gateway/messages with Content-Type: application/json
  Then the Phoenix router dispatches to GatewayController
  And SchemaInterceptor.validate/1 is called first
  And the HTTP response status is 202
  And the response body contains {"status": "accepted", "trace_id": "<uuid>"}
```

### S2: POST to wrong path returns HTTP 404
```gherkin
Scenario: POST to /gateway/message (singular) returns HTTP 404 from the router
  Given an agent that sends POST /gateway/message with a valid JSON payload
  When the Phoenix router processes the request
  Then no route matches /gateway/message
  And the HTTP response status is 404
  And GatewayController is never invoked
```

### S3: SchemaInterceptor.validate/1 is invoked as the first action in the controller
```gherkin
Scenario: schema validation failure produces 422 before any downstream processing
  Given a JSON payload that fails schema validation due to a missing required field
  When the payload is submitted to POST /gateway/messages
  Then the HTTP response status is 422
  And no PubSub broadcast occurs on "gateway:messages" before the 422 response is sent
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts a valid payload to `/gateway/messages` and asserts the response is HTTP 202 with `"status": "accepted"` and a `"trace_id"` field.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts to `/gateway/message` (singular) and asserts the response is HTTP 404.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that confirms `SchemaInterceptor.validate/1` is the first call made in the controller action by verifying a schema error on an invalid payload produces HTTP 422 before any other processing.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** HTTP POST request to `/gateway/messages`; JSON body; `Content-Type: application/json` header.
**Outputs:** HTTP 202 with `{"status": "accepted", "trace_id": "..."}` on success; HTTP 404 on wrong path; HTTP 422 on schema failure; HTTP 400 on malformed JSON.
**State changes:** On success, a PubSub broadcast on `"gateway:messages"` occurs.

## Traceability
- Parent FR: FR-7.3
- ADR: [ADR-013](../../decisions/ADR-013-hypervisor-platform-scope.md)
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
