---
id: UC-0215
title: Broadcast SchemaViolationEvent on "gateway:violations" PubSub Topic
status: draft
parent_fr: FR-7.7
adrs: [ADR-015]
---

# UC-0215: Broadcast SchemaViolationEvent on "gateway:violations" PubSub Topic

## Intent
This use case covers the PubSub broadcast of a `SchemaViolationEvent` after a validation failure. The broadcast must occur after the HTTP 422 response has been sent (or in parallel via `Task.start/1` to avoid adding latency to the response). The broadcast key must be `:schema_violation` so that LiveView subscribers can pattern-match on it in `handle_info/2`. If `Phoenix.PubSub.broadcast/3` fails, the Gateway must log a warning but must not raise or affect the HTTP response.

## Primary Actor
`Observatory.Gateway.SchemaInterceptor`

## Supporting Actors
- `Phoenix.PubSub` (broadcast mechanism)
- `Observatory.PubSub` (the application PubSub instance)
- `"gateway:violations"` (the topic that carries violation events)
- Fleet Command LiveView (example subscriber that renders violation flash messages)
- `Logger` (receives a warning if broadcast fails)

## Preconditions
- The `SchemaViolationEvent` map has been constructed (UC-0213 completed).
- The HTTP 422 response has been sent to the agent, or the broadcast is occurring in parallel via `Task.start/1`.
- `Observatory.PubSub` is started and registered.

## Trigger
The Gateway controller completes HTTP 422 response sending and initiates the `SchemaViolationEvent` broadcast, or initiates the broadcast in a `Task.start/1` to parallelize with the HTTP response.

## Main Success Flow
1. The Gateway calls `Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:violations", {:schema_violation, event})`.
2. `Phoenix.PubSub.broadcast/3` delivers the message to all subscribers of `"gateway:violations"`.
3. A subscribed Fleet Command LiveView receives `{:schema_violation, %{"agent_id" => "agent-42", ...}}` in `handle_info/2`.
4. The LiveView renders a flash message: `"Agent agent-42 (1.0.0) sent malformed message"`.
5. No page refresh is needed; the update is delivered via LiveView's WebSocket channel.

## Alternate Flows
### A1: Broadcast in parallel with HTTP 422 response
Condition: The Gateway uses `Task.start/1` to broadcast without blocking the HTTP response.
Steps:
1. The controller sends the HTTP 422 response to the agent.
2. A `Task.start/1` is initiated to call `Phoenix.PubSub.broadcast/3`.
3. The task runs concurrently; the HTTP response is not delayed by the broadcast.
4. The task completes and the event is delivered to subscribers.

## Failure Flows
### F1: Phoenix.PubSub.broadcast/3 returns {:error, reason}
Condition: `Phoenix.PubSub.broadcast/3` fails to deliver the event.
Steps:
1. The Gateway receives `{:error, reason}` from the broadcast call.
2. The Gateway calls `Logger.warning("Failed to broadcast schema_violation event: #{inspect(reason)}")`.
3. The Gateway does not raise, does not crash the controller process, and does not retry.
4. The HTTP 422 response to the agent is unaffected.
Result: The operator can observe the warning in logs. The agent's HTTP response is not changed by the broadcast failure.

## Gherkin Scenarios

### S1: Successful broadcast delivers event to LiveView subscriber
```gherkin
Scenario: SchemaViolationEvent is broadcast on "gateway:violations" and received by a LiveView
  Given a LiveView subscribed to "gateway:violations"
  And a SchemaViolationEvent has been constructed with agent_id "agent-42"
  When Phoenix.PubSub.broadcast/3 is called with {:schema_violation, event}
  Then the LiveView handle_info/2 receives {:schema_violation, event}
  And the event contains agent_id: "agent-42"
```

### S2: Broadcast failure emits a warning log without raising
```gherkin
Scenario: broadcast failure is logged as a warning and does not affect the HTTP response
  Given Phoenix.PubSub.broadcast/3 returns {:error, :no_subscribers} for a test topic
  When the Gateway attempts to broadcast the SchemaViolationEvent
  Then a warning-level log entry is emitted containing "Failed to broadcast schema_violation event"
  And no exception is raised
  And the HTTP 422 response to the agent is unchanged
```

### S3: Broadcast message key is the atom :schema_violation not a string or alternative atom
```gherkin
Scenario: PubSub broadcast uses :schema_violation atom as the message tuple key
  Given a SchemaViolationEvent is constructed after a validation failure
  When Phoenix.PubSub.broadcast/3 publishes the event on "gateway:violations"
  Then the message tuple received by subscribers has the key :schema_violation
  And the key is not the atom :violation or the string "schema_violation"
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that subscribes to `"gateway:violations"`, triggers a validation failure, and asserts the test process receives `{:schema_violation, event}` where `event` is a plain map.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that stubs `Phoenix.PubSub.broadcast/3` to return `{:error, :test_error}` and asserts a warning log is emitted and no exception is raised.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that asserts the broadcast message key is `:schema_violation` (not `:violation` or `"schema_violation"`).
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `SchemaViolationEvent` plain map (UC-0213 output); `Observatory.PubSub` instance; topic `"gateway:violations"`.
**Outputs:** PubSub message `{:schema_violation, event}` delivered to all subscribers. Warning log on broadcast failure.
**State changes:** PubSub state is updated with the broadcast; no ETS or database state is modified.

## Traceability
- Parent FR: FR-7.7
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
