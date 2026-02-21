---
id: UC-0204
title: Detect DAG Root Node via parent_step_id
status: draft
parent_fr: FR-6.5
adrs: [ADR-014, ADR-017]
---

# UC-0204: Detect DAG Root Node via parent_step_id

## Intent
This use case covers the optional `meta.parent_step_id` field and its role as the causal DAG edge indicator. A nil value marks the DecisionLog as a DAG root node with no incoming edge. The schema must not add a validation error when this field is absent. Additionally, an empty string submitted as the value must be trimmed to nil by a changeset preprocessing step so that blank strings do not masquerade as valid UUID references.

## Primary Actor
`Observatory.Mesh.DecisionLog`

## Supporting Actors
- `Observatory.Mesh.DecisionLog.Meta` (inner schema that owns parent_step_id)
- Topology Engine (FRD-008, reads parent_step_id to build directed edges)

## Preconditions
- The `Meta` embedded schema declares `field :parent_step_id, :string` without a `validate_required` constraint.
- The `Meta` changeset includes a preprocessing step that converts empty strings to nil before any UUID format check.

## Trigger
A call to `Observatory.Mesh.DecisionLog.changeset(%DecisionLog{}, params)` where `params["meta"]["parent_step_id"]` is either absent, a valid UUID string, or an empty string `""`.

## Main Success Flow
1. The caller passes a params map that omits the `"parent_step_id"` key within the `"meta"` block.
2. The `Meta` embedded changeset casts the field and stores `nil` for `:parent_step_id`.
3. No validation error is added on `:parent_step_id`.
4. `Ecto.Changeset.valid?/1` returns `true`.
5. `Ecto.Changeset.apply_changes/1` returns a struct with `meta.parent_step_id: nil`.
6. The Topology Engine reads `log.meta.parent_step_id` as `nil` and treats the node as a DAG root with no parent edge.

## Alternate Flows
### A1: Valid UUID supplied for parent_step_id
Condition: The params map contains `"parent_step_id": "550e8400-e29b-41d4-a716-446655440000"`.
Steps:
1. The `Meta` changeset casts the string UUID.
2. `parent_step_id` is stored as the UUID string.
3. No validation error is added.
4. The Topology Engine creates a directed edge from the parent step to this node.

## Failure Flows
### F1: Empty string submitted for parent_step_id
Condition: The params map contains `"parent_step_id": ""`.
Steps:
1. The `Meta` changeset preprocessing step detects the empty string.
2. The preprocessing step converts `""` to `nil` before casting.
3. `:parent_step_id` is stored as `nil`.
4. No UUID format error is added (the nil check precedes any format validation).
5. `Ecto.Changeset.valid?/1` returns `true` (assuming all other required fields are present).
Result: The node is treated as a DAG root, same as the absence case. An empty string does not produce a spurious UUID format error.

## Gherkin Scenarios

### S1: Absent parent_step_id produces nil and valid changeset
```gherkin
Scenario: parent_step_id absent from params results in nil and no validation error
  Given a params map that omits parent_step_id from the meta block
  When Observatory.Mesh.DecisionLog.changeset/2 is called with the params map
  Then Ecto.Changeset.valid?/1 returns true
  And apply_changes/1 returns a struct with meta.parent_step_id equal to nil
```

### S2: Empty string is trimmed to nil before validation
```gherkin
Scenario: parent_step_id empty string is converted to nil by the changeset trim step
  Given a params map with parent_step_id set to an empty string ""
  When Observatory.Mesh.DecisionLog.changeset/2 is called with the params map
  Then the changeset stores nil for meta.parent_step_id
  And Ecto.Changeset.valid?/1 returns true
  And no UUID format error is added to the changeset
```

### S3: Valid UUID parent_step_id is stored and produces a DAG edge
```gherkin
Scenario: valid UUID parent_step_id is stored as a string in the struct
  Given a params map with parent_step_id set to a valid UUID v4 string
  When Observatory.Mesh.DecisionLog.changeset/2 is called with the params map
  Then Ecto.Changeset.valid?/1 returns true
  And apply_changes/1 returns a struct with meta.parent_step_id equal to the UUID string
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that omits `parent_step_id` and asserts `changeset_struct.meta.parent_step_id == nil` and `Ecto.Changeset.valid?(changeset) == true`.
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that passes `"parent_step_id" => ""` and asserts the resulting struct has `meta.parent_step_id == nil` with no changeset error on `:parent_step_id`.
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that passes a valid UUID string and asserts the struct stores that UUID string in `meta.parent_step_id`.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `params["meta"]["parent_step_id"]` as absent, an empty string, or a UUID string.
**Outputs:** `meta.parent_step_id: nil` when absent or empty; `meta.parent_step_id: "<uuid>"` when a valid UUID is supplied.
**State changes:** Read-only; no state is modified.

## Traceability
- Parent FR: FR-6.5
- ADR: [ADR-014](../../decisions/ADR-014-decision-log-envelope.md)
- ADR: [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
