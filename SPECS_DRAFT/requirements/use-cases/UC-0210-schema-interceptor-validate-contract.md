---
id: UC-0210
title: SchemaInterceptor validate/1 Synchronous Validation Contract
status: draft
parent_fr: FR-7.2
adrs: [ADR-015]
---

# UC-0210: SchemaInterceptor validate/1 Synchronous Validation Contract

## Intent
This use case covers the `validate/1` function on `Observatory.Gateway.SchemaInterceptor`. The function accepts a string-keyed params map, delegates synchronously to `Observatory.Mesh.DecisionLog.changeset/2`, checks `Ecto.Changeset.valid?/1`, and returns either `{:ok, %DecisionLog{}}` or `{:error, %Ecto.Changeset{}}`. The function must be synchronous: it must complete entirely within the calling process and must not spawn any async work. The controller depends on this guarantee to return a response in the same request cycle.

## Primary Actor
`Observatory.Gateway.SchemaInterceptor`

## Supporting Actors
- `Observatory.Mesh.DecisionLog` (changeset/2 is delegated to internally)
- `Ecto.Changeset` (valid?/1 determines the return branch)
- `ObservatoryWeb.GatewayController` (the caller that depends on synchronous completion)

## Preconditions
- `Observatory.Gateway.SchemaInterceptor.validate/1` is a public function defined in `lib/observatory/gateway/schema_interceptor.ex`.
- The function body does not contain `Task.start`, `Task.async`, `GenServer.call`, or any other async primitive.
- `Observatory.Mesh.DecisionLog.changeset/2` is available.

## Trigger
`ObservatoryWeb.GatewayController` calls `SchemaInterceptor.validate(conn.body_params)` after `Plug.Parsers` has decoded the request body.

## Main Success Flow
1. The controller calls `SchemaInterceptor.validate(params)` in the same process as the HTTP request handler.
2. `validate/1` calls `DecisionLog.changeset(%DecisionLog{}, params)`.
3. `validate/1` calls `Ecto.Changeset.valid?(changeset)` and receives `true`.
4. `validate/1` calls `Ecto.Changeset.apply_changes(changeset)` and wraps the result.
5. `validate/1` returns `{:ok, %DecisionLog{}}` to the controller.
6. The controller proceeds with the struct without awaiting any async process.

## Alternate Flows

### A1: Params map missing meta.timestamp causes error return
Condition: The params map omits `meta.timestamp`.
Steps:
1. `DecisionLog.changeset/2` produces a changeset with a validation error on `:timestamp`.
2. `Ecto.Changeset.valid?(changeset)` returns `false`.
3. `validate/1` returns `{:error, changeset}`.
4. The controller pattern-matches on `{:error, changeset}` and builds the 422 response.

## Failure Flows
### F1: validate/1 spawns an async process
Condition: A developer mistakenly wraps the changeset call in `Task.start/1` or `Task.async/1`.
Steps:
1. `validate/1` returns before the task completes, causing the controller to pattern-match on an incomplete or incorrect result.
2. The controller may respond before validation finishes, allowing invalid messages to proceed.
Result: This is a code review failure. The implementation must not contain any async primitives. This constraint is verified by reading the source of `validate/1` and confirming no `Task`, `GenServer.call`, or `send/receive` are used.

## Gherkin Scenarios

### S1: Valid params return {:ok, struct} synchronously
```gherkin
Scenario: validate/1 returns {:ok, %DecisionLog{}} for a valid params map
  Given a string-keyed params map containing all required DecisionLog fields
  When SchemaInterceptor.validate/1 is called with the params map
  Then the return value is {:ok, %Observatory.Mesh.DecisionLog{}}
  And the function returns within the calling process without spawning any async work
```

### S2: Missing meta.timestamp returns {:error, changeset}
```gherkin
Scenario: validate/1 returns {:error, changeset} when meta.timestamp is absent
  Given a params map that omits meta.timestamp
  When SchemaInterceptor.validate/1 is called with the params map
  Then the return value is {:error, %Ecto.Changeset{valid?: false}}
  And the changeset errors contain timestamp: {"can't be blank", [validation: :required]}
```

### S3: validate/1 completes synchronously within the calling process
```gherkin
Scenario: validate/1 does not spawn Task, GenServer, or Process during execution
  Given SchemaInterceptor.validate/1 is called with a valid params map
  When the function returns
  Then the changeset result is available immediately in the calling process
  And the source code of validate/1 contains no Task, GenServer.call, or Process.spawn calls
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that calls `SchemaInterceptor.validate/1` with a valid params map and asserts the return matches `{:ok, %Observatory.Mesh.DecisionLog{}}`.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that calls `SchemaInterceptor.validate/1` with a params map missing `meta.timestamp` and asserts the return matches `{:error, %Ecto.Changeset{valid?: false}}`.
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that confirms no `Task`, `GenServer`, or `Process.spawn` is invoked during `validate/1` by verifying the changeset result is available immediately after the function returns.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** String-keyed params map decoded from the HTTP request body.
**Outputs:** `{:ok, %DecisionLog{}}` on success; `{:error, %Ecto.Changeset{valid?: false}}` on failure.
**State changes:** Read-only; no state is modified. The caller is responsible for side effects (PubSub broadcasts, HTTP responses).

## Traceability
- Parent FR: FR-7.2
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
