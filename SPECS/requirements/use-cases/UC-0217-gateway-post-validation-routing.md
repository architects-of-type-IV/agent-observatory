---
id: UC-0217
title: Route Validated DecisionLog to "gateway:messages" PubSub Topic
status: draft
parent_fr: FR-7.9
adrs: [ADR-015, ADR-018]
---

# UC-0217: Route Validated DecisionLog to "gateway:messages" PubSub Topic

## Intent
This use case covers the success path: after `SchemaInterceptor.validate/1` returns `{:ok, log}`, the Gateway applies the entropy_score overwrite (FR-6.7 / UC-0206), broadcasts the struct on `"gateway:messages"` with key `:decision_log`, and responds to the agent with HTTP 202 and the confirmed `trace_id`. If the PubSub broadcast fails on the success path, the Gateway must still respond HTTP 202 because the agent's message was valid and accepted; broadcast failure is an internal Observatory concern.

## Primary Actor
`ObservatoryWeb.GatewayController`

## Supporting Actors
- `Observatory.Gateway.SchemaInterceptor` (provides `{:ok, log}`)
- `Observatory.Mesh.EntropyComputer` (computes entropy_score overwrite)
- `Phoenix.PubSub` (broadcast on `"gateway:messages"`)
- `Observatory.PubSub` (application PubSub instance)
- Topology Map LiveView (subscriber, receives `{:decision_log, log}`)
- Feed LiveView (subscriber, receives `{:decision_log, log}`)
- `Logger` (warning-level on broadcast failure)

## Preconditions
- `SchemaInterceptor.validate/1` has returned `{:ok, %DecisionLog{} = log}`.
- `Observatory.Mesh.EntropyComputer.compute/1` is available.
- `Observatory.PubSub` is started and registered.
- The controller is executing within the HTTP request handler process.

## Trigger
The controller receives `{:ok, log}` from `SchemaInterceptor.validate/1`.

## Main Success Flow
1. The controller receives `{:ok, log}` from `SchemaInterceptor.validate/1`.
2. The controller checks `log.cognition` for nil.
3. `log.cognition` is not nil; the controller calls `EntropyComputer.compute(log)` and receives `0.75`.
4. The controller constructs a new struct with `cognition.entropy_score` set to `0.75`.
5. The controller calls `Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:messages", {:decision_log, updated_log})`.
6. `Phoenix.PubSub.broadcast/3` returns `:ok`.
7. The Topology Map LiveView and Feed LiveView receive `{:decision_log, updated_log}` within the PubSub delivery window.
8. The controller calls `json(conn, %{"status" => "accepted", "trace_id" => log.meta.trace_id})` and sets HTTP status to 202.
9. The agent receives HTTP 202 with the confirmed `trace_id`.

## Alternate Flows
### A1: cognition section is nil; entropy overwrite skipped
Condition: `log.cognition` is `nil`.
Steps:
1. The controller detects `log.cognition == nil`.
2. The controller skips the `EntropyComputer.compute/1` call.
3. The struct is broadcast with `cognition: nil` unchanged.
4. The HTTP 202 response proceeds as normal.

## Failure Flows
### F1: PubSub broadcast fails on success path
Condition: `Phoenix.PubSub.broadcast/3` returns `{:error, reason}`.
Steps:
1. The controller receives `{:error, reason}` from the broadcast call.
2. The controller calls `Logger.warning("Failed to broadcast decision_log: #{inspect(reason)}")`.
3. The controller does not raise or crash.
4. The controller still responds with HTTP 202 to the agent.
5. The agent's message was valid and is not asked to retry.
Result: The broadcast failure is an internal Observatory concern. Downstream LiveViews miss this message, but the agent is not penalized for an internal delivery failure.

## Gherkin Scenarios

### S1: Valid DecisionLog is entropy-overwritten and broadcast on "gateway:messages" with HTTP 202
```gherkin
Scenario: validated DecisionLog is routed to "gateway:messages" with entropy overwrite and HTTP 202
  Given SchemaInterceptor.validate/1 returns {:ok, log} with cognition.entropy_score 0.2
  And EntropyComputer.compute/1 returns 0.75 for the log
  When the controller applies the entropy overwrite and broadcasts on "gateway:messages"
  Then the broadcast message is {:decision_log, log} with cognition.entropy_score equal to 0.75
  And the HTTP response status is 202
  And the response body is {"status": "accepted", "trace_id": "<log.meta.trace_id>"}
```

### S2: PubSub broadcast failure still produces HTTP 202
```gherkin
Scenario: PubSub broadcast failure on success path does not change the HTTP 202 response
  Given SchemaInterceptor.validate/1 returns {:ok, log}
  And Phoenix.PubSub.broadcast/3 returns {:error, :delivery_failed}
  When the controller processes the success path
  Then a warning-level log entry is emitted containing "Failed to broadcast decision_log"
  And the HTTP response status is 202
  And the agent is not asked to retry
```

### S3: Broadcast key is :decision_log for downstream LiveView pattern matching
```gherkin
Scenario: broadcast message uses :decision_log key so LiveViews can pattern-match
  Given a valid DecisionLog struct is broadcast on "gateway:messages"
  When the Topology Map LiveView handle_info/2 receives the message
  Then the message pattern is {:decision_log, %Observatory.Mesh.DecisionLog{}}
  And the LiveView can access log.meta.trace_id without error
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts a valid payload, subscribes to `"gateway:messages"`, and asserts the test process receives `{:decision_log, log}` where `log` is a `%Observatory.Mesh.DecisionLog{}` struct.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that posts a valid payload and asserts the HTTP response is 202 with a `"trace_id"` field matching `log.meta.trace_id`.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that stubs `Phoenix.PubSub.broadcast/3` to return `{:error, :test_error}` on the success path and asserts the HTTP response is still 202 and a warning log is emitted.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `{:ok, %DecisionLog{}}` from `SchemaInterceptor.validate/1`; entropy score float from `EntropyComputer.compute/1`.
**Outputs:** PubSub broadcast `{:decision_log, log}` on `"gateway:messages"`; HTTP 202 response with `{"status": "accepted", "trace_id": "..."}`.
**State changes:** PubSub state is updated with the broadcast. Topology Map and Feed LiveView assigns are updated by downstream subscribers upon receipt. No ETS or database state is directly modified by the controller.

## Traceability
- Parent FR: FR-7.9
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md)
