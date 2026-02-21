---
id: UC-0002
title: Assign default view mode :overview on LiveView mount
status: draft
parent_fr: FR-1.2
adrs: [ADR-001, ADR-003, ADR-008]
---

# UC-0002: Assign Default View Mode :overview on LiveView Mount

## Intent
When `ObservatoryWeb.DashboardLive` mounts, it assigns `:overview` as the initial `:view_mode`. This initial value is a placeholder; the `StatePersistence` hook immediately fires a `"restore_state"` event that may overwrite it. This use case covers the mount itself — establishing the contract that `:overview` is always the in-process default before any restoration occurs.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardLive.mount/3`
- `StatePersistence` JS hook

## Preconditions
- A client connects to the LiveView route.
- `mount/3` is invoked by Phoenix.

## Trigger
`DashboardLive.mount/3` is called during the initial LiveView connection handshake.

## Main Success Flow
1. `DashboardLive.mount/3` is called with `params`, `session`, and `socket`.
2. `assign(socket, :view_mode, :overview)` sets the initial value.
3. The mount completes successfully; the socket is returned with `{:ok, socket}`.
4. The rendered HTML is delivered to the client with `view_mode: :overview`.
5. The `StatePersistence` hook fires `"restore_state"` immediately on client mount.
6. If localStorage contains a valid mode, `handle_event("restore_state", ...)` overwrites `:overview` with the restored mode.

## Alternate Flows

### A1: First-time operator with no localStorage entry
Condition: localStorage key `"observatory:view_mode"` does not exist.
Steps:
1. `StatePersistence` pushes `restore_state` with `view_mode: nil` or `""`.
2. `DashboardUIHandlers.maybe_restore/3` pattern-matches on `nil` or `""` and returns the socket unchanged.
3. `:view_mode` remains `:overview`.

## Failure Flows

### F1: mount/3 raises before assign completes
Condition: A dependency (e.g., PubSub subscription) raises before the `:view_mode` assign.
Steps:
1. `mount/3` raises an exception.
2. Phoenix LiveView catches the crash and renders an error page.
3. The client sees a disconnected LiveView error rather than the dashboard.
Result: No partial socket state is visible; Phoenix handles crash recovery.

## Gherkin Scenarios

### S1: Fresh mount sets view_mode to :overview
```gherkin
Scenario: LiveView mount assigns :overview as initial view_mode
  Given the LiveView route is requested by a new client connection
  When DashboardLive.mount/3 completes
  Then socket.assigns.view_mode equals :overview
  And the response is {:ok, socket}
```

### S2: First-time operator sees :overview after restore_state with no localStorage value
```gherkin
Scenario: restore_state with nil view_mode leaves :overview unchanged
  Given DashboardLive is mounted with view_mode :overview
  When the StatePersistence hook pushes restore_state with view_mode nil
  Then socket.assigns.view_mode remains :overview
```

### S3: Returning operator's restore_state overwrites :overview
```gherkin
Scenario: restore_state with stored mode overwrites default :overview
  Given DashboardLive is mounted with view_mode :overview
  When the StatePersistence hook pushes restore_state with view_mode "command"
  Then socket.assigns.view_mode equals :command
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/live/dashboard_live_test.exs` includes a test that mounts `DashboardLive` and asserts `socket.assigns.view_mode == :overview` before any `restore_state` event is sent (S1).
- [ ] A test simulates `restore_state` with `%{"view_mode" => nil}` and asserts `:view_mode` stays `:overview` (S2).
- [ ] A test simulates `restore_state` with `%{"view_mode" => "command"}` and asserts `:view_mode` becomes `:command` (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `params`, `session`, `socket` from Phoenix LiveView mount callback
**Outputs:** `{:ok, socket}` with `:view_mode` assigned `:overview`
**State changes:** `socket.assigns.view_mode = :overview` (initial); may be overwritten by `restore_state`

## Traceability
- Parent FR: [FR-1.2](../frds/FRD-001-navigation-view-architecture.md)
- ADR: [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md), [ADR-003](../../decisions/ADR-003-unified-control-plane.md), [ADR-008](../../decisions/ADR-008-default-view-evolution.md)
