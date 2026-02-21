---
id: UC-0201
title: Validate Required Fields on DecisionLog Changeset
status: draft
parent_fr: FR-6.2
adrs: [ADR-014]
---

# UC-0201: Validate Required Fields on DecisionLog Changeset

## Intent
This use case covers the enforcement of the seven required fields across the DecisionLog embedded schema hierarchy. The changeset must add Ecto validation errors for any absent or nil required field, and a DecisionLog missing any required field must not be considered valid. The Gateway relies on `Ecto.Changeset.valid?/1` to gate forwarding; this UC verifies that gate is correctly armed.

## Primary Actor
`Observatory.Mesh.DecisionLog`

## Supporting Actors
- `Ecto.Changeset` (validate_required/2, valid?/1)
- `Observatory.Gateway.SchemaInterceptor` (reads changeset validity to decide HTTP response)

## Preconditions
- `Observatory.Mesh.DecisionLog.changeset/2` is defined and compiles without warnings.
- The embedded sub-schemas `Meta`, `Identity`, `Cognition`, and `Action` each call `validate_required/2` on their respective required fields.

## Trigger
A call to `Observatory.Mesh.DecisionLog.changeset(%DecisionLog{}, params)` where `params` is either complete or missing one or more required fields.

## Main Success Flow
1. The caller passes a params map containing all seven required fields: `meta.trace_id`, `meta.timestamp`, `identity.agent_id`, `identity.agent_type`, `identity.capability_version`, `cognition.intent`, and `action.status`.
2. Each embedded changeset runs `validate_required/2` against its required fields.
3. No validation errors are added.
4. `Ecto.Changeset.valid?/1` returns `true`.
5. The Gateway forwards the struct on the success path.

## Alternate Flows
### A1: Multiple required fields absent simultaneously
Condition: The params map omits both `meta.trace_id` and `identity.agent_id`.
Steps:
1. The `Meta` embedded changeset adds an error on `:trace_id`.
2. The `Identity` embedded changeset adds an error on `:agent_id`.
3. `Ecto.Changeset.valid?/1` returns `false`.
4. The Gateway reads the changeset errors and constructs a `SchemaViolationEvent` describing the first error encountered.
5. The Gateway returns HTTP 422 to the caller.

## Failure Flows
### F1: meta.trace_id absent
Condition: The params map omits `meta.trace_id`.
Steps:
1. The `Meta` embedded changeset runs `validate_required/2` and adds an error `{"can't be blank", [validation: :required]}` on `:trace_id`.
2. `Ecto.Changeset.valid?/1` returns `false`.
3. The Gateway constructs a `SchemaViolationEvent` with `violation_reason: "missing required field: meta.trace_id"`.
4. The Gateway returns HTTP 422 to the calling agent.
Result: The message is rejected; no PubSub broadcast occurs on `"gateway:messages"`.

## Gherkin Scenarios

### S1: All required fields present produces valid changeset
```gherkin
Scenario: changeset is valid when all seven required fields are supplied
  Given a params map containing meta.trace_id, meta.timestamp, identity.agent_id, identity.agent_type, identity.capability_version, cognition.intent, and action.status
  When Observatory.Mesh.DecisionLog.changeset/2 is called with the params map
  Then Ecto.Changeset.valid?/1 returns true
  And no validation errors are present in the changeset
```

### S2: Missing meta.trace_id produces a validation error
```gherkin
Scenario: changeset is invalid when meta.trace_id is absent
  Given a params map that omits meta.trace_id
  When Observatory.Mesh.DecisionLog.changeset/2 is called with the params map
  Then Ecto.Changeset.valid?/1 returns false
  And the changeset errors include trace_id: {"can't be blank", [validation: :required]}
```

### S3: Missing cognition.intent produces a validation error
```gherkin
Scenario: changeset is invalid when cognition.intent is absent
  Given a params map that includes a cognition block but omits cognition.intent
  When Observatory.Mesh.DecisionLog.changeset/2 is called with the params map
  Then Ecto.Changeset.valid?/1 returns false
  And the changeset errors on the cognition embed include intent: {"can't be blank", [validation: :required]}
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that supplies all seven required fields and asserts `Ecto.Changeset.valid?(changeset) == true`.
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that omits `meta.trace_id` and asserts the changeset errors contain `{:trace_id, {"can't be blank", [validation: :required]}}`.
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that omits `action.status` and asserts `Ecto.Changeset.valid?(changeset) == false`.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** String-keyed params map; may be complete or partial.
**Outputs:** `%Ecto.Changeset{valid?: true}` when all required fields present; `%Ecto.Changeset{valid?: false, errors: [...]}` when any required field is absent.
**State changes:** Read-only; no state is modified.

## Traceability
- Parent FR: FR-6.2
- ADR: [ADR-014](../../decisions/ADR-014-decision-log-envelope.md)
