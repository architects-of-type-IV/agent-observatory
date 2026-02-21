---
id: UC-0008
title: Jump to feed view filtered by session_id without persisting to localStorage
status: draft
parent_fr: FR-1.8
adrs: [ADR-001, ADR-003, ADR-008]
---

# UC-0008: Jump to Feed View Filtered by Session ID Without Persisting to localStorage

## Intent
`DashboardNavigationHandlers` handles programmatic cross-view jumps that simultaneously change the view mode and apply a session filter. These jumps intentionally bypass `handle_set_view/2` so they do not push `"view_mode_changed"` and therefore do not overwrite localStorage. Selections are always cleared on every jump. This use case covers `"jump_to_feed"` as the canonical example; the same behavior applies to `"jump_to_timeline"`, `"jump_to_agents"`, and `"jump_to_tasks"`.

## Primary Actor
Operator

## Supporting Actors
- `ObservatoryWeb.DashboardNavigationHandlers`
- `ObservatoryWeb.DashboardLive` (socket assigns)

## Preconditions
- The LiveView is mounted.
- The operator is viewing an agent row or event that has a `session_id`.

## Trigger
A `phx-click` link in the UI emits `handle_event("jump_to_feed", %{"session_id" => sid}, socket)`.

## Main Success Flow
1. The operator clicks "view in feed" on an agent row with `session_id: "abc-123"`.
2. `DashboardNavigationHandlers.handle_event("jump_to_feed", %{"session_id" => "abc-123"}, socket)` is called.
3. The handler assigns `:feed` to `:view_mode`.
4. The handler assigns `"abc-123"` to `:filter_session_id`.
5. `:selected_event` is cleared (assigned `nil`).
6. `:selected_task` is cleared (assigned `nil`).
7. The Feed view renders filtered to session `"abc-123"`.
8. No `push_event("view_mode_changed", ...)` is called; localStorage retains the prior mode.

## Alternate Flows

### A1: jump_to_timeline
Condition: `"jump_to_timeline"` event fires with `session_id`.
Steps:
1. Handler assigns `:timeline` to `:view_mode` and `session_id` to `:filter_session_id`.
2. Selections are cleared.
3. No `"view_mode_changed"` push.

### A2: jump_to_agents
Condition: `"jump_to_agents"` event fires with `session_id`.
Steps:
1. Handler assigns `:agents` to `:view_mode` and `session_id` to `:filter_session_id`.
2. Selections are cleared.

### A3: jump_to_tasks
Condition: `"jump_to_tasks"` event fires with `session_id`.
Steps:
1. Handler assigns `:tasks` to `:view_mode` and `session_id` to `:filter_session_id`.
2. Selections are cleared.

## Failure Flows

### F1: jump_to_feed arrives without session_id key
Condition: Event params do not include `"session_id"`.
Steps:
1. `handle_event("jump_to_feed", %{}, socket)` does not match the `%{"session_id" => sid}` function head.
2. Phoenix raises `FunctionClauseError`.
3. The LiveView process crashes and reconnects.
Result: This is acceptable by FR-1.8 specification. All callers MUST supply `session_id`. A defensive fallback would mask bugs in callers.

## Gherkin Scenarios

### S1: jump_to_feed sets view_mode :feed and applies session filter
```gherkin
Scenario: jump_to_feed assigns :feed view and session filter
  Given the LiveView is mounted with view_mode :command
  And localStorage["observatory:view_mode"] is "command"
  When a "jump_to_feed" event fires with session_id "abc-123"
  Then socket.assigns.view_mode equals :feed
  And socket.assigns.filter_session_id equals "abc-123"
  And socket.assigns.selected_event is nil
  And socket.assigns.selected_task is nil
```

### S2: jump_to_feed does not push view_mode_changed
```gherkin
Scenario: jump_to_feed does not update localStorage
  Given localStorage["observatory:view_mode"] is "command"
  When a "jump_to_feed" event fires with session_id "abc-123"
  Then no "view_mode_changed" push event is emitted
  And localStorage["observatory:view_mode"] remains "command"
```

### S3: jump_to_feed without session_id raises FunctionClauseError
```gherkin
Scenario: Missing session_id in jump_to_feed raises FunctionClauseError
  Given the LiveView is mounted
  When a "jump_to_feed" event fires with no session_id param
  Then a FunctionClauseError is raised
```

### S4: jump_to_timeline applies correct view mode and filter
```gherkin
Scenario: jump_to_timeline assigns :timeline and session filter
  Given the LiveView is mounted with view_mode :command
  When a "jump_to_timeline" event fires with session_id "def-456"
  Then socket.assigns.view_mode equals :timeline
  And socket.assigns.filter_session_id equals "def-456"
  And socket.assigns.selected_event is nil
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/live/dashboard_live_test.exs` sends `"jump_to_feed"` with `%{"session_id" => "abc-123"}` and asserts `view_mode == :feed`, `filter_session_id == "abc-123"`, `selected_event == nil`, `selected_task == nil` (S1).
- [ ] The same test asserts that no `push_event("view_mode_changed", ...)` is called during the jump (S2).
- [ ] A test sends `"jump_to_feed"` with empty params `%{}` and asserts `FunctionClauseError` is raised (S3).
- [ ] A test sends `"jump_to_timeline"` with `%{"session_id" => "def-456"}` and asserts `view_mode == :timeline` and `filter_session_id == "def-456"` (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `%{"session_id" => string}` event params
**Outputs:** Updated `:view_mode`, `:filter_session_id`, cleared `:selected_event` and `:selected_task`
**State changes:** `socket.assigns.view_mode`, `socket.assigns.filter_session_id`, `socket.assigns.selected_event = nil`, `socket.assigns.selected_task = nil`

## Traceability
- Parent FR: [FR-1.8](../frds/FRD-001-navigation-view-architecture.md)
- ADR: [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md), [ADR-003](../../decisions/ADR-003-unified-control-plane.md), [ADR-008](../../decisions/ADR-008-default-view-evolution.md)
