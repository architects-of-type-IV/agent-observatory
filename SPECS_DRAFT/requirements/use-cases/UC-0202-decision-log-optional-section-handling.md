---
id: UC-0202
title: Handle Optional Embedded Sections in DecisionLog
status: draft
parent_fr: FR-6.3
adrs: [ADR-014]
---

# UC-0202: Handle Optional Embedded Sections in DecisionLog

## Intent
This use case covers the behavior of the DecisionLog changeset when one or more of its six embedded sub-schema sections is entirely absent from the incoming payload. All sections are cast with `cast_embed/3` using the `optional: true` flag, which means their absence must not produce a validation error. A minimal payload containing only the seven required fields must produce a valid changeset with `cognition: nil`, `state_delta: nil`, and `control: nil`. The Gateway must tolerate these nil sections without raising during entropy alerting or downstream processing.

## Primary Actor
`Observatory.Mesh.DecisionLog`

## Supporting Actors
- `Ecto.Changeset` (cast_embed/3 with optional: true)
- `Observatory.Gateway.SchemaInterceptor` (skips entropy alerting when cognition is nil)
- `Observatory.Mesh.EntropyComputer` (skipped when cognition is nil)

## Preconditions
- `Observatory.Mesh.DecisionLog.changeset/2` is defined.
- All six embedded sections use `cast_embed(:section, optional: true)`.
- The Gateway entropy alerting path checks `cognition` for nil before calling `EntropyComputer.compute/1`.

## Trigger
A call to `Observatory.Mesh.DecisionLog.changeset(%DecisionLog{}, params)` where `params` contains only the required root fields and omits one or more embedded section blocks entirely.

## Main Success Flow
1. The caller passes a minimal params map containing the seven required fields and no `"cognition"`, `"state_delta"`, or `"control"` keys.
2. `cast_embed/3` for each absent section stores `nil` in the corresponding field of the changeset.
3. No validation errors are added for the absent sections.
4. `Ecto.Changeset.valid?/1` returns `true`.
5. `Ecto.Changeset.apply_changes/1` returns a `%DecisionLog{}` with `cognition: nil`, `state_delta: nil`, and `control: nil`.
6. The Gateway receives the struct and detects `cognition == nil`.
7. The Gateway skips the entropy alerting step entirely and does not call `EntropyComputer.compute/1`.
8. The struct is broadcast on `"gateway:messages"` with `cognition: nil`.

## Alternate Flows
### A1: cognition block present but intent absent
Condition: The params map includes a `"cognition"` key but omits `"intent"` within it.
Steps:
1. `cast_embed/3` processes the cognition block and runs the `Cognition` embedded changeset.
2. The `Cognition` changeset calls `validate_required/2` on `:intent`.
3. A validation error is added: `intent: {"can't be blank", [validation: :required]}`.
4. `Ecto.Changeset.valid?/1` returns `false`.
5. The Gateway rejects the message with HTTP 422.

## Failure Flows
### F1: Gateway dereferences nil cognition without a nil guard
Condition: Gateway code calls `log.cognition.entropy_score` without checking for nil first.
Steps:
1. `log.cognition` is `nil`.
2. Elixir raises `UndefinedFunctionError` or a nil dereference error.
3. The controller process crashes.
Result: The HTTP response is a 500 error rather than the expected 202. This failure is prevented by the nil guard requirement in FR-6.3 and FR-6.7.

## Gherkin Scenarios

### S1: Minimal payload with absent optional sections is valid
```gherkin
Scenario: changeset is valid and optional sections are nil when only required fields are supplied
  Given a params map containing only the seven required fields with no cognition, state_delta, or control keys
  When Observatory.Mesh.DecisionLog.changeset/2 is called with the params map
  Then Ecto.Changeset.valid?/1 returns true
  And apply_changes/1 returns a struct with cognition: nil, state_delta: nil, and control: nil
```

### S2: cognition block present but missing intent causes rejection
```gherkin
Scenario: changeset is invalid when a cognition block is present but omits the required intent field
  Given a params map that includes a cognition block without an intent field
  When Observatory.Mesh.DecisionLog.changeset/2 is called with the params map
  Then Ecto.Changeset.valid?/1 returns false
  And the changeset errors on the cognition embed include intent: {"can't be blank", [validation: :required]}
```

### S3: Gateway skips entropy alerting when cognition is nil
```gherkin
Scenario: entropy alerting is bypassed when the DecisionLog has no cognition section
  Given a validated DecisionLog struct with cognition: nil
  When the Gateway processes the struct for broadcast
  Then EntropyComputer.compute/1 is not called
  And the struct is broadcast on "gateway:messages" with cognition: nil
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that supplies only the seven required fields and asserts `changeset.changes.cognition == nil` and `Ecto.Changeset.valid?(changeset) == true`.
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that supplies a cognition block without `intent` and asserts `Ecto.Changeset.valid?(changeset) == false`.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that sends a minimal DecisionLog struct with `cognition: nil` through the Gateway processing path and asserts no `FunctionClauseError` or nil dereference is raised.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** String-keyed params map; may omit any of the six embedded section keys entirely.
**Outputs:** `%Ecto.Changeset{valid?: true}` with absent sections stored as `nil`; or `%Ecto.Changeset{valid?: false}` if a present section fails its own required-field validation.
**State changes:** Read-only; no state is modified.

## Traceability
- Parent FR: FR-6.3
- ADR: [ADR-014](../../decisions/ADR-014-decision-log-envelope.md)
