---
id: UC-0206
title: Overwrite Agent-Reported entropy_score Before PubSub Broadcast
status: draft
parent_fr: FR-6.7
adrs: [ADR-014, ADR-018]
---

# UC-0206: Overwrite Agent-Reported entropy_score Before PubSub Broadcast

## Intent
This use case covers the Gateway's mandatory entropy_score overwrite step. An agent-submitted `cognition.entropy_score` is treated as informational only and must be replaced with the value computed by `Observatory.Mesh.EntropyComputer.compute/1` before the struct is broadcast on `"gateway:messages"`. The overwrite must happen after changeset validation succeeds and before the PubSub broadcast. When the `cognition` section is nil, the overwrite step must be skipped entirely to avoid nil dereference.

## Primary Actor
`Observatory.Gateway.SchemaInterceptor`

## Supporting Actors
- `Observatory.Mesh.EntropyComputer` (compute/1 produces the canonical entropy score)
- `Phoenix.PubSub` (receives the overwritten struct on "gateway:messages")
- `Observatory.Mesh.DecisionLog` (struct whose cognition.entropy_score is replaced)

## Preconditions
- `SchemaInterceptor.validate/1` has returned `{:ok, log}`.
- `log.cognition` is either a populated `%Cognition{}` struct or `nil`.
- `Observatory.Mesh.EntropyComputer.compute/1` is defined and accepts a `%DecisionLog{}` struct.

## Trigger
The Gateway controller calls the entropy overwrite step after receiving `{:ok, log}` from `SchemaInterceptor.validate/1` and before calling `Phoenix.PubSub.broadcast/3`.

## Main Success Flow
1. The Gateway receives `{:ok, log}` from `SchemaInterceptor.validate/1`.
2. The Gateway checks that `log.cognition` is not nil.
3. The Gateway calls `Observatory.Mesh.EntropyComputer.compute(log)` and receives a float value (e.g., `0.75`).
4. The Gateway constructs a new struct with `cognition.entropy_score` set to `0.75`, replacing the agent-submitted value (e.g., `0.2`).
5. The Gateway broadcasts the updated struct on `"gateway:messages"` with key `:decision_log`.
6. The agent-submitted `entropy_score` of `0.2` is discarded and never appears in the broadcast.

## Alternate Flows
### A1: cognition section is nil, overwrite skipped
Condition: `log.cognition` is `nil`.
Steps:
1. The Gateway checks `log.cognition` and finds `nil`.
2. The Gateway skips the call to `EntropyComputer.compute/1`.
3. The Gateway broadcasts the struct with `cognition: nil` unchanged.
4. No `FunctionClauseError` or nil dereference error is raised.

## Failure Flows
### F1: EntropyComputer.compute/1 raises an exception
Condition: `EntropyComputer.compute/1` raises an unexpected exception.
Steps:
1. The Gateway's entropy overwrite step propagates the exception.
2. The controller process handles the error (e.g., via `rescue` or a supervisor restart).
3. The HTTP response behavior under this failure is governed by the application's error-handling strategy (out of scope for this UC).
Result: This failure case is identified as a gap to be addressed in the EntropyComputer FRD (FRD-009).

## Gherkin Scenarios

### S1: Agent-submitted entropy_score is replaced with computed value
```gherkin
Scenario: cognition.entropy_score is overwritten with EntropyComputer value before broadcast
  Given a validated DecisionLog struct with cognition.entropy_score set to 0.2
  And EntropyComputer.compute/1 returns 0.75 for the struct
  When the Gateway applies the entropy overwrite step
  Then the struct broadcast on "gateway:messages" has cognition.entropy_score equal to 0.75
  And the original agent-submitted value of 0.2 is discarded
```

### S2: entropy_score overwrite is skipped when cognition is nil
```gherkin
Scenario: entropy overwrite step is bypassed when cognition section is nil
  Given a validated DecisionLog struct with cognition equal to nil
  When the Gateway applies the entropy overwrite step
  Then EntropyComputer.compute/1 is not called
  And the struct broadcast on "gateway:messages" has cognition equal to nil
  And no error is raised
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that stubs `EntropyComputer.compute/1` to return `0.75` and asserts the broadcast struct has `cognition.entropy_score == 0.75` while the original submitted value was different.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that provides a struct with `cognition: nil` and asserts `EntropyComputer.compute/1` is not called and no error is raised.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `%DecisionLog{}` struct from `SchemaInterceptor.validate/1`; `EntropyComputer.compute/1` return value (float).
**Outputs:** Updated `%DecisionLog{}` struct with `cognition.entropy_score` replaced by the computed value, or unchanged struct when `cognition` is nil.
**State changes:** The struct broadcast on `"gateway:messages"` carries the computed entropy_score. No ETS or database state is modified.

## Traceability
- Parent FR: FR-6.7
- ADR: [ADR-014](../../decisions/ADR-014-decision-log-envelope.md)
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md)
