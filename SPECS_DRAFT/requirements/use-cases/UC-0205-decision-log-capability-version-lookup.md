---
id: UC-0205
title: Validate and Look Up capability_version on Ingest
status: draft
parent_fr: FR-6.6
adrs: [ADR-014]
---

# UC-0205: Validate and Look Up capability_version on Ingest

## Intent
This use case covers the `identity.capability_version` field, which carries a semver string identifying the schema version the sending agent uses. The schema enforces only that the field is a non-empty string. After schema validation succeeds, the Gateway looks up the version in `Observatory.Gateway.CapabilityMap`. An active registered version proceeds silently; an unknown or deprecated version still proceeds but triggers a warning-level log entry so operators can detect fleet drift.

## Primary Actor
`Observatory.Gateway.SchemaInterceptor`

## Supporting Actors
- `Observatory.Mesh.DecisionLog` (changeset validates non-empty string)
- `Observatory.Gateway.CapabilityMap` (version registry, looks up registration and active status)
- `Logger` (warning-level log when version is unknown or deprecated)

## Preconditions
- `identity.capability_version` is declared in the `Identity` embedded schema as `field :capability_version, :string`.
- `validate_required/2` is applied to `:capability_version` within the `Identity` changeset.
- `Observatory.Gateway.CapabilityMap` exposes a lookup function (e.g., `lookup/1`) that returns `{:ok, :active}`, `{:ok, :deprecated}`, or `{:error, :unknown}`.

## Trigger
`SchemaInterceptor.validate/1` is called with a params map; after changeset validation returns valid, the Gateway calls `CapabilityMap.lookup/1` with the capability_version string.

## Main Success Flow
1. The params map contains `"capability_version": "2.0.0"` within the `"identity"` block.
2. `DecisionLog.changeset/2` validates the field is a non-empty string; no error is added.
3. `Ecto.Changeset.valid?/1` returns `true`.
4. The Gateway extracts the struct and calls `CapabilityMap.lookup("2.0.0")`.
5. `CapabilityMap` returns `{:ok, :active}`.
6. The message is forwarded to `"gateway:messages"` without emitting a warning log.

## Alternate Flows
### A1: Unknown version accepted with warning log
Condition: `"capability_version": "0.9.0"` is not registered in `CapabilityMap`.
Steps:
1. Changeset validation passes (non-empty string check succeeds).
2. The Gateway calls `CapabilityMap.lookup("0.9.0")` and receives `{:error, :unknown}`.
3. The Gateway emits a warning-level log entry including `agent_id` and `"0.9.0"`.
4. The message is still forwarded to `"gateway:messages"`.
5. The HTTP response is HTTP 202.

### A2: Deprecated version accepted with warning log
Condition: `"capability_version": "1.0.0"` is registered but marked deprecated.
Steps:
1. Changeset validation passes.
2. `CapabilityMap.lookup("1.0.0")` returns `{:ok, :deprecated}`.
3. The Gateway emits a warning-level log entry.
4. The message is forwarded.

## Failure Flows
### F1: Empty capability_version string causes HTTP 422
Condition: The params map contains `"capability_version": ""`.
Steps:
1. `validate_required/2` in the `Identity` changeset detects an empty string (Ecto treats blank strings as missing for required fields when `validate_required` is applied to cast fields).
2. A validation error `{"can't be blank", [validation: :required]}` is added on `:capability_version`.
3. `Ecto.Changeset.valid?/1` returns `false`.
4. The Gateway returns HTTP 422; `CapabilityMap` is never called.
Result: The message is rejected.

## Gherkin Scenarios

### S1: Active registered version proceeds without warning
```gherkin
Scenario: capability_version "2.0.0" is active in CapabilityMap and proceeds silently
  Given a params map with identity.capability_version set to "2.0.0"
  And CapabilityMap is configured to return {:ok, :active} for "2.0.0"
  When SchemaInterceptor.validate/1 is called and changeset validation passes
  Then CapabilityMap.lookup/1 is called with "2.0.0"
  And no warning log is emitted
  And the message is forwarded on "gateway:messages"
```

### S2: Unknown version is accepted but emits a warning log
```gherkin
Scenario: capability_version "0.9.0" is unknown and triggers a warning log but proceeds
  Given a params map with identity.capability_version set to "0.9.0"
  And CapabilityMap returns {:error, :unknown} for "0.9.0"
  When SchemaInterceptor.validate/1 is called and changeset validation passes
  Then a warning-level log entry is emitted containing "0.9.0" and the agent_id
  And the HTTP response status is 202
  And the message is forwarded on "gateway:messages"
```

### S3: Empty capability_version causes HTTP 422
```gherkin
Scenario: empty string capability_version fails validate_required and produces HTTP 422
  Given a params map with identity.capability_version set to an empty string
  When SchemaInterceptor.validate/1 is called
  Then the changeset errors include capability_version: {"can't be blank", [validation: :required]}
  And the HTTP response status is 422
  And CapabilityMap.lookup/1 is not called
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/decision_log_test.exs` passes a test that passes an empty string for `capability_version` and asserts the changeset error includes `{:capability_version, {"can't be blank", [validation: :required]}}`.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that stubs `CapabilityMap.lookup/1` to return `{:error, :unknown}` and asserts a warning log is emitted and the return is `{:ok, log}`.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that stubs `CapabilityMap.lookup/1` to return `{:ok, :active}` and asserts no warning log is emitted.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `params["identity"]["capability_version"]` as a semver string or empty string.
**Outputs:** `{:ok, %DecisionLog{}}` with warning log side effect when version is unknown/deprecated; `{:error, changeset}` when field is blank.
**State changes:** Read-only; warning log is a side effect. No ETS or database state is modified.

## Traceability
- Parent FR: FR-6.6
- ADR: [ADR-014](../../decisions/ADR-014-decision-log-envelope.md)
