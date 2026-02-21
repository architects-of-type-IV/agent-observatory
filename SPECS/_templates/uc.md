---
id: UC-NNNN
title: <Concise action-oriented title>
status: draft
parent_fr: FR-NNNN
adrs: [ADR-NNN]
---

# UC-NNNN: <Title matching frontmatter>

## Intent
<1 paragraph describing what this use case accomplishes and under what conditions.
State the specific system behavior being verified.>

## Primary Actor
<Single actor. For field-definition and resource UCs, prefer "API Client".
For step-behavior UCs, prefer the named pipeline step (e.g., "Ash Reactor Step").
Never list two primary actors.>

## Supporting Actors
- <Ash resource, adapter, or infrastructure component involved>
- <Database layer or index>
- <Job or worker if applicable>

## Preconditions
- A valid `group_id` tenant context is active.
- <Additional state that must be true before the trigger fires.>
- <Be specific: name the resource, field values, and how the setup state is created.>

## Trigger
<What event or call initiates this use case.>

## Main Success Flow
1. <First step -- actor or system action.>
2. <Next step.>
3. <Continue numbering sequentially.>

## Alternate Flows

### A1: <Alternate condition name>
Condition: <When this alternate applies.>
Steps:
1. <What happens differently.>
2. <Outcome.>

<!-- Repeat A2, A3, ... as needed. Omit section content (leave "None") if no alternates exist. -->

## Failure Flows

### F1: <Failure condition name>
Condition: <What goes wrong.>
Steps:
1. <System behavior on failure.>
2. <Error propagation or retry behavior.>
Result: <Final state after failure -- emphasize safety and idempotency.>

<!-- Repeat F2, F3, ... as needed. -->

## Gherkin Scenarios

### S1: <Main success scenario name>
```gherkin
Scenario: <Descriptive name matching Main Success Flow>
  Given <precondition setup -- map from Preconditions section>
  And <additional precondition if needed>
  When <trigger action -- map from Trigger section>
  Then <primary assertion -- expected outcome>
  And <secondary assertion if needed>
```

### S2: <Alternate or failure scenario name>
```gherkin
Scenario: <Descriptive name matching an Alternate or Failure Flow>
  Given <precondition setup>
  When <trigger with failure/alternate condition>
  Then <expected error behavior or alternate outcome>
```

<!-- One scenario per Main Success Flow + each Alternate Flow + each Failure Flow.
     Number sequentially: S1, S2, S3, ...
     Each scenario must map to exactly one AC checkbox below. -->

## Acceptance Criteria
- [ ] `mix test <test_file_path>` passes a test that <describes what the test asserts>.
- [ ] <Additional machine-verifiable criterion.>
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data

**Inputs:** <What goes into the operation -- field names, types, sources.>

**Outputs:** <What comes out -- return values, created/updated records.>

**State changes:** <Side effects on database, graph, indexes. Use "Read-only; no state is modified." for queries.>

## Traceability
- Parent FR: [FR-NNNN](../frs/FR-NNNN-name.md)
- ADR: [ADR-NNN](../../decisions/ADR-NNN-name.md)
