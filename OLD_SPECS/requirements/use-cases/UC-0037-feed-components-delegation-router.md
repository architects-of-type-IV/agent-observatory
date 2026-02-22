---
id: UC-0037
title: Delegate feed component calls through FeedComponents without adding logic
status: draft
parent_fr: FR-2.13
adrs: [ADR-002]
---

# UC-0037: Delegate Feed Component Calls Through FeedComponents Without Adding Logic

## Intent
`ObservatoryWeb.Components.FeedComponents` is a pure delegation module. It defines `feed_view/1`, `session_group/1`, `tool_execution_block/1`, and `standalone_event/1` by forwarding to the corresponding functions in the `ObservatoryWeb.Components.Feed.*` child modules. Callers import `FeedComponents` and use all four functions without referencing child modules directly. No business logic, conditional rendering, or data transformation may live in `FeedComponents` itself.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.Components.FeedComponents`
- `ObservatoryWeb.Components.Feed.FeedView`
- `ObservatoryWeb.Components.Feed.SessionGroup`
- `ObservatoryWeb.Components.Feed.ToolExecutionBlock`
- `ObservatoryWeb.Components.Feed.StandaloneEvent`

## Preconditions
- All four child modules are compiled and define their respective component functions.
- A caller template imports `ObservatoryWeb.Components.FeedComponents`.

## Trigger
A LiveView template calls `<.session_group group={group} .../>` after importing `FeedComponents`.

## Main Success Flow
1. A LiveView template imports `ObservatoryWeb.Components.FeedComponents`.
2. The template calls `<.session_group group={group} feed_hidden_types={@feed_hidden_types} .../>`.
3. `FeedComponents.session_group/1` delegates the call directly to `Feed.SessionGroup.session_group/1`.
4. No intermediate transformation or conditional occurs in `FeedComponents`.
5. The session block renders correctly as if called directly from `SessionGroup`.

## Alternate Flows

### A1: feed_view/1 delegation
Condition: A caller uses `<.feed_view .../>` from `FeedComponents`.
Steps:
1. `FeedComponents.feed_view/1` delegates to `Feed.FeedView.feed_view/1`.
2. The full feed view renders.

### A2: tool_execution_block/1 delegation
Condition: A caller uses `<.tool_execution_block pair={pair}/>` from `FeedComponents`.
Steps:
1. `FeedComponents.tool_execution_block/1` delegates to `Feed.ToolExecutionBlock.tool_execution_block/1`.
2. The tool execution block renders.

### A3: standalone_event/1 delegation
Condition: A caller uses `<.standalone_event event={event}/>` from `FeedComponents`.
Steps:
1. `FeedComponents.standalone_event/1` delegates to `Feed.StandaloneEvent.standalone_event/1`.
2. The standalone event row renders.

## Failure Flows

### F1: Logic added to FeedComponents violates the delegation contract
Condition: A developer adds a conditional or data transformation inside `FeedComponents.session_group/1`.
Steps:
1. FR-2.13 is violated.
2. The module is no longer a pure delegation router.
Result: Detection: code review and a test asserting `FeedComponents.session_group/1` has no body other than a delegation call.

### F2: Child module not imported causes undefined function error
Condition: `Feed.SessionGroup` is not compiled or its module name changes.
Steps:
1. `FeedComponents.session_group/1` attempts to call `Feed.SessionGroup.session_group/1`.
2. Elixir raises `UndefinedFunctionError` at call time.
3. The LiveView process crashes.
Result: `mix compile --warnings-as-errors` catches undefined function references at compile time.

## Gherkin Scenarios

### S1: session_group/1 call delegates without modification
```gherkin
Scenario: Calling session_group/1 through FeedComponents renders the same output as calling SessionGroup directly
  Given a session group map with session_id "test-session"
  When a LiveView template calls <.session_group group={group}/> after importing FeedComponents
  Then the rendered HTML is identical to calling Feed.SessionGroup.session_group/1 directly
```

### S2: FeedComponents.session_group/1 has no conditional logic
```gherkin
Scenario: FeedComponents contains no business logic in session_group/1
  Given the FeedComponents module source code
  When the source of session_group/1 is inspected
  Then the function body contains only a delegation call to Feed.SessionGroup.session_group/1
  And no if/case/cond expressions are present in the body
```

### S3: All four delegation functions compile without errors
```gherkin
Scenario: All four FeedComponents delegation functions compile successfully
  Given all four Feed.* child modules are compiled
  When mix compile runs
  Then FeedComponents defines feed_view/1, session_group/1, tool_execution_block/1, and standalone_event/1
  And no UndefinedFunctionError warnings are emitted
```

### S4: Caller imports FeedComponents and accesses all four functions
```gherkin
Scenario: A LiveView template can call all four component functions via FeedComponents import
  Given a LiveView template imports ObservatoryWeb.Components.FeedComponents
  When the template calls <.feed_view/>, <.session_group/>, <.tool_execution_block/>, <.standalone_event/>
  Then all four calls render without UndefinedFunctionError
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/components/feed_components_test.exs` includes a test rendering `session_group/1` via `FeedComponents` and asserting the output matches direct `SessionGroup.session_group/1` output (S1).
- [ ] A code inspection test or assertion verifies that `FeedComponents.session_group/1` function body contains no `if`/`case`/`cond` expressions (S2).
- [ ] `mix compile --warnings-as-errors` passes, confirming all four delegation targets are defined (S3).
- [ ] A test that calls all four component functions via `FeedComponents` import asserts no `UndefinedFunctionError` is raised (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Component assigns (varies per function: `group`, `pair`, `event`, etc.)
**Outputs:** Delegated render output — identical to calling the child module directly
**State changes:** None (pure delegation and rendering)

## Traceability
- Parent FR: [FR-2.13](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
