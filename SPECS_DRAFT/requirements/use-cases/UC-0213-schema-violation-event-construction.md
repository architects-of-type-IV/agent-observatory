---
id: UC-0213
title: Construct SchemaViolationEvent After Validation Failure
status: draft
parent_fr: FR-7.5
adrs: [ADR-015]
---

# UC-0213: Construct SchemaViolationEvent After Validation Failure

## Intent
This use case covers the construction of a `SchemaViolationEvent` plain map after `SchemaInterceptor.validate/1` returns `{:error, changeset}`. The event must include exactly six fields: `event_type`, `timestamp`, `agent_id`, `capability_version`, `violation_reason`, and `raw_payload_hash`. The event is a plain Elixir map (not an Ecto struct) because it is broadcast directly over PubSub and consumed by UI subscribers that pattern-match on map keys. Agent identity fields must default to `"unknown"` when absent from the raw params.

## Primary Actor
`Observatory.Gateway.SchemaInterceptor`

## Supporting Actors
- `ObservatoryWeb.GatewayController` (calls SchemaInterceptor, triggers event construction)
- `Observatory.PubSub` (receives the broadcast event on `"gateway:violations"`)
- `:crypto` (SHA-256 hash computation for `raw_payload_hash`)
- `Base` (hex encoding the hash digest)

## Preconditions
- `SchemaInterceptor.validate/1` has returned `{:error, changeset}`.
- The raw request body string (or a JSON-encoded fallback of the params map) is available for hashing.
- The current UTC datetime is obtainable via `DateTime.utc_now/0` or equivalent.

## Trigger
The controller receives `{:error, changeset}` and initiates the rejection path, which includes constructing and broadcasting the `SchemaViolationEvent`.

## Main Success Flow
1. The controller receives `{:error, changeset}` from `SchemaInterceptor.validate/1`.
2. The Gateway extracts `agent_id` from `params["identity"]["agent_id"]`; defaults to `"unknown"` if absent.
3. The Gateway extracts `capability_version` from `params["identity"]["capability_version"]`; defaults to `"unknown"` if absent.
4. The Gateway derives `violation_reason` from the first changeset error (e.g., `"missing required field: meta.trace_id"`).
5. The Gateway computes `raw_payload_hash` using `:crypto.hash(:sha256, raw_body)` hex-encoded lowercase and prefixed with `"sha256:"`.
6. The Gateway constructs the event map with all six fields set.
7. The event is broadcast on `"gateway:violations"` (covered in UC-0215).
8. The event map is a plain `%{}`, not an Ecto struct.

## Alternate Flows
### A1: Raw request body unavailable (already consumed by Plug.Parsers)
Condition: The raw body string is no longer available at the point of event construction.
Steps:
1. The Gateway JSON-encodes the params map using `Jason.encode!/1` as a fallback.
2. The hash is computed over the JSON-encoded params string.
3. `raw_payload_hash` is set to the resulting `"sha256:..."` string.
4. The `raw_payload_hash` field is never omitted from the event.

## Failure Flows
### F1: agent_id absent from params
Condition: The params map does not contain `params["identity"]["agent_id"]` (e.g., identity block itself is missing).
Steps:
1. The Gateway attempts to read `params["identity"]["agent_id"]`.
2. The path returns `nil`.
3. The Gateway substitutes `"unknown"` for the `agent_id` field in the event map.
4. Event construction continues without error.
Result: The event carries `"agent_id" => "unknown"`.

## Gherkin Scenarios

### S1: Well-formed rejection event is constructed with all six fields
```gherkin
Scenario: SchemaViolationEvent is constructed with all required fields after validation failure
  Given a validation failure with params containing identity.agent_id "agent-42" and identity.capability_version "1.0.0"
  And the raw request body is available for hashing
  When the Gateway constructs the SchemaViolationEvent
  Then the event is a plain Elixir map (not an Ecto struct)
  And the event contains event_type: "schema_violation"
  And the event contains agent_id: "agent-42"
  And the event contains capability_version: "1.0.0"
  And the event contains violation_reason describing the first validation error
  And the event contains raw_payload_hash prefixed with "sha256:"
  And the event contains timestamp in ISO 8601 format
```

### S2: Absent agent_id defaults to "unknown" in the event
```gherkin
Scenario: agent_id defaults to "unknown" when identity block is absent from params
  Given a validation failure with params that do not include an identity block
  When the Gateway constructs the SchemaViolationEvent
  Then the event contains agent_id: "unknown"
  And event construction completes without error
```

### S3: raw_payload_hash falls back to params JSON when raw body is unavailable
```gherkin
Scenario: raw_payload_hash is computed from JSON-encoded params when raw body is unavailable
  Given a validation failure where the raw request body string is no longer accessible
  When the Gateway constructs the SchemaViolationEvent
  Then the event contains a raw_payload_hash field prefixed with "sha256:"
  And the hash is computed from the JSON-encoded params map
  And the raw_payload_hash field is not nil or absent
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that triggers a validation failure with known `agent_id` and `capability_version` values and asserts the constructed event map contains all six required keys.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that triggers a validation failure with no identity block and asserts `event["agent_id"] == "unknown"`.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that asserts `event["raw_payload_hash"]` starts with `"sha256:"` and is a non-empty string.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** `{:error, changeset}`, `params` map (string-keyed), raw request body or params JSON fallback.
**Outputs:** Plain Elixir map with keys `"event_type"`, `"timestamp"`, `"agent_id"`, `"capability_version"`, `"violation_reason"`, `"raw_payload_hash"`.
**State changes:** The event map is broadcast on `"gateway:violations"` as a side effect (UC-0215). No ETS or database state is modified during construction.

## Traceability
- Parent FR: FR-7.5
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
