---
id: UC-0246
title: Overwrite Agent-Reported entropy_score with Gateway-Computed Value
status: draft
parent_fr: FR-9.8
adrs: [ADR-018, ADR-015]
---

# UC-0246: Overwrite Agent-Reported entropy_score with Gateway-Computed Value

## Intent
The Gateway must discard the agent's self-reported `cognition.entropy_score` and replace it with the value computed by `EntropyTracker.record_and_score/2`. This ensures all downstream consumers see a consistent, externally validated score rather than an agent's potentially self-serving or incorrect report. If `record_and_score/2` returns an error, the original agent-reported value must be preserved and a `schema_violation` log entry must be emitted. The overwrite must occur in `SchemaInterceptor` synchronously — never via async dispatch.

## Primary Actor
SchemaInterceptor

## Supporting Actors
- EntropyTracker (called synchronously via `record_and_score/2`)
- DecisionLog envelope (field `cognition.entropy_score`)
- Downstream DecisionLog subscribers (receive the authoritative score)

## Preconditions
- `SchemaInterceptor` has successfully validated the incoming DecisionLog message against the schema.
- `EntropyTracker` GenServer is running.
- The DecisionLog envelope carries a `cognition.entropy_score` field (possibly agent-reported).

## Trigger
`SchemaInterceptor` calls `EntropyTracker.record_and_score/2` after successful schema validation and receives a `{:ok, score, severity}` result.

## Main Success Flow
1. An agent sends a DecisionLog with `cognition.entropy_score: 0.9` (self-reported as healthy).
2. `SchemaInterceptor` validates the message schema successfully.
3. `SchemaInterceptor` calls `EntropyTracker.record_and_score("sess-abc", {"plan", "write_file", :success})` synchronously.
4. `EntropyTracker` returns `{:ok, 0.15, :loop}`.
5. `SchemaInterceptor` sets `cognition.entropy_score: 0.15` in the outbound DecisionLog envelope.
6. The original agent-reported value `0.9` is discarded and not stored in any field.
7. `SchemaInterceptor` broadcasts the updated DecisionLog to downstream subscribers.
8. Downstream consumers receive the envelope with `cognition.entropy_score: 0.15`.

## Alternate Flows
### A1: SchemaInterceptor call contract — synchronous, not async
Condition: Standard path; applies to every call.
Steps:
1. `record_and_score/2` is called inline within the `SchemaInterceptor` message processing function.
2. The call is NOT wrapped in `Task.async` or `GenServer.cast`.
3. The overwrite of `cognition.entropy_score` uses the value from the synchronous return.

## Failure Flows
### F1: record_and_score/2 returns an error
Condition: `EntropyTracker.record_and_score/2` returns `{:error, :missing_agent_id}` or another error tuple.
Steps:
1. `SchemaInterceptor` receives the error tuple.
2. `SchemaInterceptor` does NOT overwrite `cognition.entropy_score` with the error tuple.
3. The original agent-reported value is retained in the outbound envelope.
4. `SchemaInterceptor` emits a `schema_violation` log entry noting the failed entropy computation.
5. The DecisionLog is broadcast with the original `cognition.entropy_score` value unchanged.
Result: Downstream consumers receive the original score; the violation is logged for operator review.

### F2: DecisionLog fails schema validation — record_and_score not called
Condition: The DecisionLog message fails schema validation in `SchemaInterceptor`.
Steps:
1. `SchemaInterceptor` rejects the message.
2. `EntropyTracker.record_and_score/2` is NOT called.
3. The session's sliding window is not updated.
Result: Only valid cognition events influence entropy state.

## Gherkin Scenarios

### S1: Gateway-computed score overwrites agent self-report
```gherkin
Scenario: SchemaInterceptor replaces agent-reported entropy score with Gateway-computed value
  Given a DecisionLog arrives with cognition.entropy_score 0.9 from agent "agent-7"
  And the message passes schema validation
  And EntropyTracker.record_and_score returns {:ok, 0.15, :loop}
  When SchemaInterceptor processes the message
  Then the outbound DecisionLog has cognition.entropy_score set to 0.15
  And the original value 0.9 is not present in any field of the outbound message
```

### S2: record_and_score error retains original score and logs violation
```gherkin
Scenario: Entropy computation error preserves original score and logs schema_violation
  Given a DecisionLog arrives with cognition.entropy_score 0.7
  And EntropyTracker.record_and_score returns {:error, :missing_agent_id}
  When SchemaInterceptor processes the message
  Then the outbound DecisionLog retains cognition.entropy_score 0.7
  And a schema_violation log entry is emitted referencing the failed entropy computation
```

### S3: Schema-invalid message does not trigger entropy recording
```gherkin
Scenario: Schema validation failure prevents EntropyTracker call
  Given a DecisionLog arrives that fails schema validation
  When SchemaInterceptor processes the message
  Then EntropyTracker.record_and_score/2 is not called
  And the session sliding window remains unchanged
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that simulates the `SchemaInterceptor` overwrite path and asserts the outbound envelope carries the Gateway-computed score, not the agent-reported value.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test where `record_and_score/2` returns `{:error, :missing_agent_id}` and asserts the original `cognition.entropy_score` is preserved in the outbound envelope and a `schema_violation` log entry is produced.
- [ ] `mix test test/observatory/gateway/entropy_tracker_test.exs` passes a test that delivers a schema-invalid message and asserts `record_and_score/2` is never called.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Validated DecisionLog envelope with agent-reported `cognition.entropy_score`; `{:ok, score, severity}` from `record_and_score/2`.
**Outputs:** Outbound DecisionLog with `cognition.entropy_score` overwritten; or original score retained + violation log on error.
**State changes:** `cognition.entropy_score` field in the outbound message is mutated from agent value to Gateway value.

## Traceability
- Parent FR: FR-9.8, FR-9.9
- ADR: [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md), [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
