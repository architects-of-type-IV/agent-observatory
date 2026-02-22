---
id: UC-0214
title: Apply raw_payload_hash Security Policy to Rejected Payloads
status: draft
parent_fr: FR-7.6
adrs: [ADR-015]
---

# UC-0214: Apply raw_payload_hash Security Policy to Rejected Payloads

## Intent
This use case covers the security constraint that rejected payloads must never be stored, logged, or broadcast in raw form. Only a SHA-256 hash prefixed with `"sha256:"` may appear in the `SchemaViolationEvent`. The raw payload must not enter ETS, be written to disk, appear in logs at any level, or be included in any PubSub broadcast. This policy prevents untrusted agent-supplied content from contaminating Observatory's storage or log streams while still enabling forensic correlation via hash comparison with an external audit log.

## Primary Actor
`Observatory.Gateway.SchemaInterceptor`

## Supporting Actors
- `:crypto` (SHA-256 hash computation)
- `Base` (hex encoding)
- `Logger` (must NOT receive the raw payload)
- Phoenix PubSub (must NOT receive the raw payload)

## Preconditions
- The raw request body has been parsed by `Plug.Parsers` into a params map.
- The raw body string is available before Plug consumes it (e.g., via `Plug.Conn.read_body/2` or a custom body reader that stores the raw bytes).
- The `SchemaViolationEvent` is being constructed (UC-0213 preconditions are met).

## Trigger
The Gateway is about to construct the `raw_payload_hash` field for a `SchemaViolationEvent`.

## Main Success Flow
1. The raw request body bytes are available as a binary string.
2. The Gateway calls `:crypto.hash(:sha256, raw_body)` to produce a 32-byte binary digest.
3. The Gateway calls `Base.encode16(digest, case: :lower)` to produce a 64-character lowercase hex string.
4. The Gateway prepends `"sha256:"` to produce `"sha256:4d7a8c..."`.
5. The `raw_payload_hash` field in the `SchemaViolationEvent` is set to this string.
6. The raw body binary is not stored in ETS, not written to disk, and not passed to `Logger` at any log level.
7. The `SchemaViolationEvent` broadcast contains only the hash, not the original content.

## Alternate Flows
### A1: Raw body unavailable; fallback to params JSON hash
Condition: The raw body string is no longer accessible because `Plug.Parsers` consumed it without storing it separately.
Steps:
1. The Gateway calls `Jason.encode!(params)` to produce a JSON string representation of the parsed params.
2. The Gateway hashes the JSON string with `:crypto.hash(:sha256, json_string)`.
3. The result is hex-encoded and prefixed as `"sha256:"`.
4. The hash is computed over the JSON-encoded params, not the original raw bytes; this difference is acceptable as a fallback.
5. The `raw_payload_hash` field is set and not omitted.

## Failure Flows
### F1: Developer logs the raw payload
Condition: A developer adds `Logger.debug("rejected payload: #{inspect(params)}")` to the rejection branch.
Steps:
1. The raw params are logged to the application log stream.
2. Untrusted agent-supplied content enters the log infrastructure.
3. This is a security policy violation.
4. The violation must be caught in code review.
5. The `@moduledoc` of `SchemaInterceptor` must document this constraint so contributors see it during development.
Result: The log line must be removed before the PR is merged. The constraint is documented, not automatically enforced in Phase 1.

### F2: Raw payload included in PubSub broadcast
Condition: The `SchemaViolationEvent` is constructed with a `"raw_payload"` key containing the params map.
Steps:
1. The event is broadcast on `"gateway:violations"`.
2. Any LiveView subscriber receives the raw params as part of the event.
3. Untrusted content enters the UI layer.
4. This is a security policy violation caught in code review.
Result: The `"raw_payload"` key must be removed from the event before the PR is merged.

## Gherkin Scenarios

### S1: Hash is computed from raw body and included in the event
```gherkin
Scenario: raw_payload_hash is a SHA-256 hex digest prefixed with "sha256:"
  Given the raw request body is available as a binary string
  When the Gateway constructs the raw_payload_hash field
  Then the hash is computed using :crypto.hash(:sha256, raw_body)
  And the result is hex-encoded in lowercase and prefixed with "sha256:"
  And the raw body bytes are not stored, logged, or broadcast
```

### S2: Raw payload never appears in Logger output or PubSub events
```gherkin
Scenario: rejected payload content is excluded from all Logger and PubSub outputs
  Given a validation failure with an arbitrary rejected payload
  When the Gateway processes the rejection
  Then no Logger call receives the raw params or body as an argument
  And the SchemaViolationEvent broadcast on "gateway:violations" contains no "raw_payload" key
  And the SchemaViolationEvent contains only the "raw_payload_hash" key with the hash value
```

### S3: Logger output contains no parameter field values from a rejected payload
```gherkin
Scenario: CaptureLog asserts no parameter field values appear in log output during rejection
  Given a params map containing arbitrary string values in required fields
  When SchemaInterceptor.validate/1 rejects the payload and processes the schema violation
  Then ExUnit.CaptureLog captures no log output containing those parameter field values
  And the Logger warning that is emitted contains only the raw_payload_hash and the violation reason
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that asserts `event["raw_payload_hash"]` starts with `"sha256:"` and has a length of exactly 71 characters (7 for the prefix plus 64 hex characters).
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that asserts the `SchemaViolationEvent` map does not contain a `"raw_payload"` key.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that asserts `Logger` is not called with any representation of the params map in the rejection path (verified via `ExUnit.CaptureLog` asserting no log output contains parameter field values).
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** Raw request body binary or JSON-encoded params fallback.
**Outputs:** `"raw_payload_hash"` string in the format `"sha256:<64 hex chars>"`.
**State changes:** Read-only computation. The hash is included in the event broadcast; no raw payload data is persisted or logged.

## Traceability
- Parent FR: FR-7.6
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
