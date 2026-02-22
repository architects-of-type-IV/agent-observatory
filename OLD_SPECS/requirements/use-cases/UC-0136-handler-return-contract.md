---
id: UC-0136
title: Return bare socket from handler functions not noreply tuple
status: draft
parent_fr: FR-5.12
adrs: [ADR-011]
---

# UC-0136: Return Bare Socket from Handler Functions Not noreply Tuple

## Intent
Handler functions in all `Dashboard*Handlers` modules return a bare `Phoenix.LiveView.Socket` struct. The `{:noreply, socket}` wrapping is applied exclusively at the call site in `DashboardLive`, typically via the `prepare_assigns/1` wrapper pattern. Returning a tuple from a handler causes a `KeyError` when `prepare_assigns/1` is applied to the result.

## Primary Actor
Developer

## Supporting Actors
- `ObservatoryWeb.DashboardLive` (applies the wrapping)
- `prepare_assigns/1` function
- `mix compile --warnings-as-errors`

## Preconditions
- A `Dashboard*Handlers` module exists with one or more handler functions.
- `DashboardLive` imports the handler module and delegates via `handle_event/3` or `handle_info/2`.

## Trigger
A developer writes a new handler function or reviews an existing one.

## Main Success Flow
1. Developer writes a handler function: `def handle_filter(params, socket), do: assign(socket, :filter, params)`.
2. The function returns `socket` (a `%Phoenix.LiveView.Socket{}` struct).
3. `DashboardLive` delegates: `def handle_event("filter", p, s), do: {:noreply, handle_filter(p, s) |> prepare_assigns()}`.
4. `prepare_assigns/1` receives a socket and recomputes derived assigns correctly.
5. `{:noreply, socket}` is returned to the LiveView runtime.
6. `mix compile --warnings-as-errors` passes with zero warnings.

## Alternate Flows

### A1: Alternative delegation form
Condition: Developer uses the pipeline form instead of the delegation form.
Steps:
1. `def handle_event("filter", p, s), do: handle_filter(p, s) |> then(&{:noreply, prepare_assigns(&1)})`.
2. Both forms are equivalent; either is acceptable.

## Failure Flows

### F1: Handler returns {:noreply, socket} tuple
Condition: A handler function returns `{:noreply, socket}` instead of `socket`.
Steps:
1. `DashboardLive` calls `prepare_assigns(handle_filter(p, s))`.
2. `prepare_assigns/1` receives `{:noreply, socket}` instead of `socket`.
3. `prepare_assigns/1` calls `socket.assigns` on a tuple, raising `KeyError`.
4. The LiveView process crashes and is restarted by the supervisor.
5. Developer corrects the handler to return bare `socket`.
6. `mix compile --warnings-as-errors` passes after correction.
Result: The runtime crash (not a compile error) is the signal; handlers returning tuples must be corrected.

## Gherkin Scenarios

### S1: Handler returning bare socket integrates correctly
```gherkin
Scenario: Handler returns bare socket and prepare_assigns wraps it correctly
  Given DashboardFilterHandlers.handle_filter/2 returns socket
  When handle_event("filter", params, socket) is dispatched
  Then {:noreply, prepared_socket} is returned to the LiveView runtime
  And prepare_assigns has been called exactly once on the result
```

### S2: Handler returning tuple causes KeyError at runtime
```gherkin
Scenario: Handler returning {:noreply, socket} causes a KeyError in prepare_assigns
  Given a handler function returns {:noreply, socket}
  When DashboardLive calls prepare_assigns(handle_filter(p, s))
  Then prepare_assigns raises KeyError because it received a tuple not a socket
  And the LiveView process crashes
```

## Acceptance Criteria
- [ ] `grep -rn "{:noreply," lib/observatory_web/live/dashboard_*_handlers.ex` returns no matches (all handler modules return bare sockets) (S1).
- [ ] `grep -rn "prepare_assigns" lib/observatory_web/live/dashboard_live.ex` shows `prepare_assigns` applied at the `DashboardLive` call sites, not inside handler modules (S1).
- [ ] `mix compile --warnings-as-errors` passes (S1).

## Data
**Inputs:** Handler function body; socket with current assigns
**Outputs:** Updated socket (bare `%Phoenix.LiveView.Socket{}`)
**State changes:** Socket assigns modified by handler; `{:noreply, ...}` wrapping applied by `DashboardLive`

## Traceability
- Parent FR: [FR-5.12](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-011](../../decisions/ADR-011-handler-delegation.md)
