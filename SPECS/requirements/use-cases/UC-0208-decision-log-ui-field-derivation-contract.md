---
id: UC-0208
title: Enforce UI Field Derivation Contract for DecisionLog Schema
status: draft
parent_fr: FR-6.9
adrs: [ADR-014]
---

# UC-0208: Enforce UI Field Derivation Contract for DecisionLog Schema

## Intent
This use case covers the stability contract between six specific DecisionLog fields and the UI components that derive their behavior from those fields. The contract specifies that `meta.parent_step_id`, `cognition.reasoning_chain`, `cognition.entropy_score`, `state_delta.cumulative_session_cost`, `control.hitl_required`, and `control.is_terminal` are reserved derivation anchors. Pattern matching on these fields in LiveView modules must be safe because the schema always declares them (even if nil). Any rename or removal of these fields constitutes a breaking change requiring a major version bump.

## Primary Actor
`Observatory.Mesh.DecisionLog`

## Supporting Actors
- Topology Map LiveView (reads `meta.parent_step_id` and `control.is_terminal`)
- Reasoning Playback component (reads `cognition.reasoning_chain`)
- Entropy Alert subsystem (reads `cognition.entropy_score`)
- Cost Heatmap component (reads `state_delta.cumulative_session_cost`)
- HITL Gate component (reads `control.hitl_required`)

## Preconditions
- The `DecisionLog` schema declares all six derivation anchor fields.
- LiveView components subscribe to `"gateway:messages"` and receive `%DecisionLog{}` structs.
- Pattern matching on the struct is performed directly (e.g., `log.meta.parent_step_id`).

## Trigger
A LiveView component receives a `{:decision_log, log}` message from `"gateway:messages"` and accesses one or more of the six derivation anchor fields.

## Main Success Flow
1. A validated `%DecisionLog{}` struct is broadcast on `"gateway:messages"`.
2. The Topology Map LiveView receives the struct and reads `log.meta.parent_step_id`.
3. `parent_step_id` is always present in the struct (possibly nil); pattern matching does not raise.
4. The Topology Map uses the value to construct a directed edge (if non-nil) or mark the node as a DAG root (if nil).
5. Each other LiveView component reads its respective derivation anchor field safely.

## Alternate Flows
### A1: Field is nil but declared in schema
Condition: `log.control` is nil (the `control` section was absent from the payload).
Steps:
1. The HITL Gate component attempts to read `log.control.hitl_required`.
2. Because `log.control` is nil, the component must guard against nil access before dereferencing nested fields.
3. The component treats nil control as `hitl_required: false` per its default behavior.
4. No crash occurs.

## Failure Flows
### F1: Breaking schema change applied without major version bump
Condition: A developer renames `state_delta.cumulative_session_cost` to `state_delta.total_cost` without updating the Cost Heatmap or incrementing the capability_version major.
Steps:
1. The Cost Heatmap component reads `log.state_delta.cumulative_session_cost` and receives `nil` (field no longer exists under that name).
2. The heatmap renders incorrectly or with missing data.
3. The schema version in `identity.capability_version` still reads `"2.0.0"`, so no N-1 drift warning fires.
Result: Silent data loss in the UI. This failure is prevented by the breaking-change policy in FR-6.9 and the code review process that treats field renames as requiring an ADR update.

## Gherkin Scenarios

### S1: Topology Map safely reads parent_step_id from broadcast struct
```gherkin
Scenario: parent_step_id is always accessible on a broadcast DecisionLog struct
  Given a DecisionLog struct has been validated and broadcast on "gateway:messages"
  When the Topology Map LiveView receives the struct
  Then log.meta.parent_step_id is accessible without raising KeyError or UndefinedFunctionError
  And the field is either a UUID string or nil
```

### S2: HITL Gate handles nil control section without crashing
```gherkin
Scenario: HITL Gate component handles nil control section gracefully
  Given a DecisionLog struct with control equal to nil
  When the HITL Gate component reads the struct
  Then no nil dereference error is raised
  And the component treats hitl_required as false
```

### S3: Field rename without version bump causes silent data loss
```gherkin
Scenario: renaming cumulative_session_cost without version bump silently breaks Cost Heatmap
  Given a DecisionLog schema where state_delta.cumulative_session_cost has been renamed to total_cost
  And the capability_version major has not been incremented
  When the Cost Heatmap reads log.state_delta.cumulative_session_cost from a broadcast struct
  Then the field returns nil because the field no longer exists under its old name
  And the Cost Heatmap renders with missing cost data
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that builds a `%DecisionLog{}` struct and asserts all six derivation anchor fields (`meta.parent_step_id`, `cognition.reasoning_chain`, `cognition.entropy_score`, `state_delta.cumulative_session_cost`, `control.hitl_required`, `control.is_terminal`) are accessible without raising, even when the corresponding embedded section is nil.
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that asserts the `DecisionLog` schema declares all six derivation anchor fields by their exact current names (`parent_step_id`, `reasoning_chain`, `entropy_score`, `cumulative_session_cost`, `hitl_required`, `is_terminal`) so that any field rename causes this test to fail and alerts the developer to increment the major version.
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that builds a DecisionLog struct with control set to nil and asserts that reading log.control.hitl_required does not raise an error and that the value is treated as false.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `%DecisionLog{}` struct received from `"gateway:messages"` PubSub broadcast.
**Outputs:** Field values (possibly nil) accessed by LiveView components; no return value from the use case itself.
**State changes:** Read-only; no state is modified.

## Traceability
- Parent FR: FR-6.9
- ADR: [ADR-014](../../decisions/ADR-014-decision-log-envelope.md)
