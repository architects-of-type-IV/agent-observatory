---
id: UC-0209
title: Enforce Gateway and UI Module Boundary
status: draft
parent_fr: FR-7.1
adrs: [ADR-013, ADR-015]
---

# UC-0209: Enforce Gateway and UI Module Boundary

## Intent
This use case covers the architectural constraint that `Observatory.Gateway.*` modules must never import, alias, or call `ObservatoryWeb.*` modules, and vice versa. Communication between the two namespaces must occur exclusively via Phoenix PubSub topics. This boundary is documented in the `SchemaInterceptor` moduledoc and enforced by code review in Phase 1. A LiveView that needs schema violation data subscribes to `"gateway:violations"` rather than calling `SchemaInterceptor` directly.

## Primary Actor
`Observatory.Gateway.SchemaInterceptor`

## Supporting Actors
- `ObservatoryWeb` LiveView modules (subscribers, not callers)
- Phoenix PubSub (the exclusive cross-boundary communication channel)
- `"gateway:violations"` (PubSub topic used for boundary-compliant event delivery)

## Preconditions
- `Observatory.Gateway.SchemaInterceptor` is defined in `lib/observatory/gateway/schema_interceptor.ex`.
- The `@moduledoc` of `SchemaInterceptor` documents the no-cross-import boundary constraint.
- No `alias ObservatoryWeb.*` or `import ObservatoryWeb.*` appears in any `Observatory.Gateway.*` module.
- No `alias Observatory.Gateway.*` or `import Observatory.Gateway.*` appears in any `ObservatoryWeb.*` module.

## Trigger
A developer adds code that crosses the module boundary; this use case describes both the correct (compliant) pattern and the incorrect (non-compliant) pattern that must be caught in code review.

## Main Success Flow
1. A LiveView component needs to display schema violations in the UI.
2. The LiveView calls `Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:violations")` in its `mount/3` callback.
3. The LiveView receives `{:schema_violation, event}` messages in its `handle_info/2` callback.
4. The LiveView renders the violation data from the event map.
5. `SchemaInterceptor` is never called directly from the LiveView.
6. `mix compile --warnings-as-errors` passes with zero warnings.

## Alternate Flows
### A1: Gateway module needs UI data
Condition: A Gateway module needs information typically held in a LiveView (e.g., subscription count).
Steps:
1. The Gateway module broadcasts a request event on a PubSub topic.
2. A LiveView processes the request and publishes a response on a second PubSub topic.
3. The Gateway module subscribes to the response topic.
4. No direct module call crosses the boundary.

## Failure Flows
### F1: LiveView directly aliases SchemaInterceptor
Condition: A developer writes `alias Observatory.Gateway.SchemaInterceptor` in a LiveView module and calls `SchemaInterceptor.validate/1`.
Steps:
1. The code compiles without error in Phase 1 (no automated Credo check enforces this yet).
2. Code review detects the boundary violation and flags it as a blocking review comment.
3. The developer is required to replace the direct call with a PubSub subscription pattern.
Result: The direct call is not merged. The boundary violation is treated as a blocking issue in code review.

## Gherkin Scenarios

### S1: LiveView subscribes to PubSub instead of calling SchemaInterceptor directly
```gherkin
Scenario: LiveView receives schema violation data via PubSub without calling SchemaInterceptor
  Given a LiveView module subscribed to "gateway:violations"
  When the Gateway broadcasts a schema_violation event on "gateway:violations"
  Then the LiveView handle_info/2 receives {:schema_violation, event}
  And the LiveView renders the violation without having called SchemaInterceptor.validate/1 directly
```

### S2: Direct alias of SchemaInterceptor in a LiveView is caught by code review
```gherkin
Scenario: boundary violation caught when a LiveView aliases Observatory.Gateway.SchemaInterceptor
  Given a LiveView module that aliases Observatory.Gateway.SchemaInterceptor
  When mix compile --warnings-as-errors is run
  Then the build passes (no automated enforcement in Phase 1)
  And a code reviewer flags the alias as a blocking boundary violation
  And the violation is documented in the SchemaInterceptor @moduledoc
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/schema_interceptor_test.exs` passes a test that verifies no `ObservatoryWeb` module is imported or aliased in `Observatory.Gateway.SchemaInterceptor` by inspecting the module's AST or by confirming the module compiles with its moduledoc containing the boundary constraint.
- [ ] `mix test test/observatory_web/controllers/gateway_controller_test.exs` passes a test that confirms `GatewayController` receives schema violation data via a PubSub broadcast pattern rather than a direct `SchemaInterceptor` call from any LiveView.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** None at runtime; this UC is primarily a structural constraint.
**Outputs:** PubSub events flow from `Observatory.Gateway.*` to `ObservatoryWeb.*` subscribers.
**State changes:** Read-only; the boundary constraint is enforced by code structure, not runtime state.

## Traceability
- Parent FR: FR-7.1
- ADR: [ADR-013](../../decisions/ADR-013-hypervisor-platform-scope.md)
- ADR: [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md)
