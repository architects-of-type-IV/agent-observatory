---
id: UC-0253
title: SchemaInterceptor Calls EntropyTracker Synchronously After Validation
status: draft
parent_fr: FR-9.9
adrs: [ADR-018, ADR-015]
---

# UC-0253: SchemaInterceptor Calls EntropyTracker Synchronously After Validation

## Intent
`SchemaInterceptor` must call `EntropyTracker.record_and_score/2` synchronously in the same process, after every successful schema validation, with arguments `(session_id, {intent, tool_call, action_status})`. The call must never be dispatched via `Task.async` or cast. Messages that fail schema validation must not trigger an entropy call, ensuring that only valid cognition events are reflected in the sliding window. The return value `{:ok, score, severity}` drives the `cognition.entropy_score` overwrite (per FR-9.8).

## Primary Actor
`Observatory.Gateway.SchemaInterceptor`

## Supporting Actors
- `Observatory.Gateway.EntropyTracker` (synchronous callee)
- DecisionLog schema validator (determines valid/invalid status)

## Preconditions
- `SchemaInterceptor` is running in the Gateway message-processing pipeline.
- `EntropyTracker` GenServer is running.
- An inbound DecisionLog message has arrived.

## Trigger
`SchemaInterceptor` completes schema validation of a DecisionLog message.

## Main Success Flow
1. `SchemaInterceptor` receives a DecisionLog message for session `"sess-abc"`.
2. Schema validation passes — all required fields are present and correctly typed.
3. `SchemaInterceptor` extracts `{intent, tool_call, action_status}` from the validated envelope.
4. `SchemaInterceptor` calls `EntropyTracker.record_and_score("sess-abc", {"plan", "write_file", :success})` synchronously.
5. `EntropyTracker` returns `{:ok, 0.6, :normal}` in the same process call.
6. `SchemaInterceptor` overwrites `cognition.entropy_score` with `0.6` in the outbound envelope.
7. The enriched DecisionLog is broadcast to downstream subscribers.

## Alternate Flows
### A1: EntropyTracker returns LOOP severity
Condition: The computed score is < 0.25.
Steps:
1. `SchemaInterceptor` receives `{:ok, 0.2, :loop}`.
2. It sets `cognition.entropy_score: 0.2` in the outbound envelope.
3. It records the `:loop` severity in the DecisionLog metadata as specified by the schema.
4. The enriched message is broadcast.

## Failure Flows
### F1: Schema validation fails — entropy call must NOT occur
Condition: The incoming DecisionLog is missing a required field (e.g., `identity.agent_id`).
Steps:
1. `SchemaInterceptor` rejects the message after schema validation.
2. `EntropyTracker.record_and_score/2` is NOT called.
3. The session's sliding window is not modified.
4. A `schema_violation` event is emitted.
Result: Invalid messages never pollute the entropy window; the session's uniqueness ratio reflects only valid cognition events.

### F2: EntropyTracker returns an error
Condition: `EntropyTracker.record_and_score/2` returns `{:error, :missing_agent_id}`.
Steps:
1. `SchemaInterceptor` receives the error tuple.
2. It does NOT overwrite `cognition.entropy_score` with the error tuple.
3. The original agent-reported value is retained in the outbound envelope.
4. A `schema_violation` log entry is emitted noting the failed entropy computation.

## Gherkin Scenarios

### S1: Valid message triggers synchronous entropy call and score overwrite
```gherkin
Scenario: Valid DecisionLog triggers synchronous EntropyTracker call
  Given SchemaInterceptor receives a DecisionLog with intent "plan", tool_call "write_file", action_status :success for session "sess-abc"
  When schema validation passes
  Then EntropyTracker.record_and_score/2 is called synchronously with "sess-abc" and {"plan", "write_file", :success}
  And the outbound envelope has cognition.entropy_score set to the value returned by EntropyTracker
```

### S2: Invalid message does not trigger entropy call
```gherkin
Scenario: Failed schema validation prevents EntropyTracker call
  Given SchemaInterceptor receives a DecisionLog missing the required field identity.agent_id
  When schema validation fails
  Then EntropyTracker.record_and_score/2 is NOT called
  And the session sliding window entry count remains unchanged
  And a schema_violation event is emitted
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that processes a valid DecisionLog and asserts `EntropyTracker.record_and_score/2` was called with the correct `session_id` and tuple, and that `cognition.entropy_score` in the outbound message equals the value returned by `EntropyTracker`.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that processes a schema-invalid DecisionLog and asserts `EntropyTracker.record_and_score/2` was never called and the session's sliding window size did not increase.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** Validated DecisionLog envelope containing `session_id`, `cognition.intent`, `action.tool_call`, `action.action_status`.
**Outputs:** Enriched outbound DecisionLog with `cognition.entropy_score` overwritten; `EntropyTracker` sliding window updated.
**State changes:** `EntropyTracker` ETS window updated for the session; outbound message `cognition.entropy_score` replaced with Gateway-computed value.

## Traceability
- Parent FR: FR-9.9
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md), [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
