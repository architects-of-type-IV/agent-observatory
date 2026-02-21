---
id: UC-0134
title: Keep DashboardLive under 300 lines via handler delegation
status: draft
parent_fr: FR-5.10
adrs: [ADR-011]
---

# UC-0134: Keep DashboardLive Under 300 Lines via Handler Delegation

## Intent
`ObservatoryWeb.DashboardLive` must remain under 300 lines and contain only lifecycle callbacks. Domain-specific logic is delegated to imported handler modules. When the module exceeds 300 lines, the excess logic is extracted into a new or existing handler module.

## Primary Actor
Developer

## Supporting Actors
- `Dashboard*Handlers` modules (imported into `DashboardLive`)
- `mix compile --warnings-as-errors`

## Preconditions
- `DashboardLive` exists and is the main Phoenix LiveView module.
- At least one `Dashboard*Handlers` module exists and is imported.

## Trigger
A developer adds new event handling logic to `DashboardLive` and observes or is notified that the file exceeds 300 lines.

## Main Success Flow
1. Developer identifies domain-specific logic in `DashboardLive` that can be delegated.
2. Developer creates a new `Dashboard{Domain}Handlers` module (e.g., `DashboardAnalyticsHandlers`).
3. The logic is moved to the handler module as functions that return `socket` (not `{:noreply, socket}`).
4. `DashboardLive` imports the new module and delegates via a single `handle_event` dispatch line.
5. `wc -l lib/observatory_web/live/dashboard_live.ex` returns a value under 300.
6. `mix compile --warnings-as-errors` passes with zero warnings.

## Alternate Flows

### A1: Logic fits in an existing handler module
Condition: The new logic belongs to the same domain as an existing handler (e.g., messaging).
Steps:
1. The function is added to `DashboardMessagingHandlers` instead of a new module.
2. `DashboardLive` gains a dispatch line referencing the existing import.
3. `wc -l lib/observatory_web/live/dashboard_live.ex` remains under 300.

## Failure Flows

### F1: Logic added directly to dashboard_live.ex
Condition: A 50-line block of formatting logic is added inline to a `handle_event` clause.
Steps:
1. Code review identifies the inline block.
2. The block is moved to the appropriate handler module.
3. `mix compile --warnings-as-errors` passes after extraction.
4. `wc -l lib/observatory_web/live/dashboard_live.ex` returns a value under 300.
Result: `DashboardLive` is restored to dispatch-only responsibility.

## Gherkin Scenarios

### S1: DashboardLive is under 300 lines after delegation
```gherkin
Scenario: Excess logic is extracted and DashboardLive drops below 300 lines
  Given dashboard_live.ex is 350 lines with inline event handling logic
  When the domain logic is moved to DashboardAnalyticsHandlers
  Then wc -l lib/observatory_web/live/dashboard_live.ex returns a number below 300
  And mix compile --warnings-as-errors passes
```

### S2: DashboardLive contains only lifecycle callbacks
```gherkin
Scenario: DashboardLive contains only mount, handle_info, handle_event, and prepare_assigns
  Given the current dashboard_live.ex
  When it is reviewed for non-lifecycle functions
  Then no domain logic functions (formatting, filtering, computation) appear in the file
  And all domain logic is in imported Dashboard*Handlers modules
```

## Acceptance Criteria
- [ ] `wc -l lib/observatory_web/live/dashboard_live.ex` returns a value less than 300 (S1).
- [ ] `grep -c "defp\|def [a-z]" lib/observatory_web/live/dashboard_live.ex` returns a count representing only `mount`, `handle_info`, `handle_event`, and `prepare_assigns` (S2).
- [ ] `mix compile --warnings-as-errors` passes (S1).

## Data
**Inputs:** `DashboardLive` source file; domain-specific logic to delegate
**Outputs:** Reduced `dashboard_live.ex`; new or extended `Dashboard*Handlers` module
**State changes:** Source tree may gain a new handler module; `dashboard_live.ex` shrinks

## Traceability
- Parent FR: [FR-5.10](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-011](../../decisions/ADR-011-handler-delegation.md)
