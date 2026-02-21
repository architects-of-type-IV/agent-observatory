---
id: UC-0200
title: Define DecisionLog Embedded Schema Module
status: draft
parent_fr: FR-6.1
adrs: [ADR-014]
---

# UC-0200: Define DecisionLog Embedded Schema Module

## Intent
This use case covers the definition of the `Observatory.Mesh.DecisionLog` module as an Ecto embedded schema containing six inner sub-schemas. The changeset function must accept a raw params map and return a populated `%Ecto.Changeset{}`. This is a schema-definition contract verified at compile time and through a direct changeset call.

## Primary Actor
`Observatory.Mesh.DecisionLog`

## Supporting Actors
- `Ecto.Schema` (embedded_schema macro)
- `Observatory.Mesh.DecisionLog.Changesets` (optional overflow module for helpers)

## Preconditions
- The file `lib/observatory/mesh/decision_log.ex` exists and compiles without warnings.
- `mix compile --warnings-as-errors` passes.

## Trigger
A call to `Observatory.Mesh.DecisionLog.changeset(%DecisionLog{}, params)` with a valid params map.

## Main Success Flow
1. The caller constructs a string-keyed params map containing all required fields.
2. The caller invokes `Observatory.Mesh.DecisionLog.changeset(%DecisionLog{}, params)`.
3. The module casts root fields and delegates to each of the six `cast_embed/3` calls: `Meta`, `Identity`, `Cognition`, `Action`, `StateDelta`, and `Control`.
4. Each embedded changeset applies its own `cast/4` and `validate_required/2` rules.
5. The function returns an `%Ecto.Changeset{}`.
6. `Ecto.Changeset.valid?/1` returns `true`.
7. The caller extracts the struct via `Ecto.Changeset.apply_changes/1`; all six embedded sections are populated or `nil` as determined by the input.

## Alternate Flows
### A1: Changeset helper extraction
Condition: The `decision_log.ex` module approaches 300 lines.
Steps:
1. Helper changeset functions are moved to `Observatory.Mesh.DecisionLog.Changesets`.
2. `DecisionLog.changeset/2` delegates to the helpers module.
3. `mix compile --warnings-as-errors` still passes with zero warnings.

## Failure Flows
### F1: Module defined outside lib/observatory/mesh/
Condition: A developer places the module in a different directory, causing an alias mismatch.
Steps:
1. `mix compile --warnings-as-errors` detects the module alias mismatch.
2. The build fails with a compilation error identifying the mismatched namespace.
Result: The build is non-green until the module is relocated to `lib/observatory/mesh/decision_log.ex`.

## Gherkin Scenarios

### S1: Valid params produce a populated changeset
```gherkin
Scenario: changeset/2 returns a valid changeset for a fully populated params map
  Given the module Observatory.Mesh.DecisionLog is defined in lib/observatory/mesh/decision_log.ex
  And the module uses embedded_schema with six embeds_one sub-schemas
  When changeset/2 is called with a params map containing all required fields
  Then Ecto.Changeset.valid?/1 returns true
  And Ecto.Changeset.apply_changes/1 returns a %DecisionLog{} struct with all six embedded sections
```

### S2: Module outside mesh directory fails build
```gherkin
Scenario: module alias mismatch causes compile-time failure
  Given a developer places the DecisionLog module outside lib/observatory/mesh/
  When mix compile --warnings-as-errors is run
  Then the build fails with a module alias mismatch error
  And the failure message identifies the incorrect module location
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that calls `Observatory.Mesh.DecisionLog.changeset(%DecisionLog{}, valid_params)` and asserts `Ecto.Changeset.valid?(changeset) == true`.
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that calls `Ecto.Changeset.apply_changes(changeset)` and asserts the result is a `%Observatory.Mesh.DecisionLog{}` struct.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** String-keyed params map with nested `"meta"`, `"identity"`, `"cognition"`, `"action"`, `"state_delta"`, and `"control"` keys.
**Outputs:** `%Ecto.Changeset{valid?: true}` on success.
**State changes:** Read-only; no state is modified.

## Traceability
- Parent FR: FR-6.1
- ADR: [ADR-014](../../decisions/ADR-014-decision-log-envelope.md)
