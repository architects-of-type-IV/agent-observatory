---
id: UC-0135
title: Name new handler modules with Dashboard prefix and domain suffix
status: draft
parent_fr: FR-5.11
adrs: [ADR-011]
---

# UC-0135: Name New Handler Modules with Dashboard Prefix and Domain Suffix

## Intent
All handler modules that contain delegated `DashboardLive` logic must follow the naming convention `ObservatoryWeb.Dashboard{Domain}Handlers`. Modules with different names are not imported by `DashboardLive` and cannot participate in the delegation pattern. The convention is enforced at code review and verifiable by grep.

## Primary Actor
Developer

## Supporting Actors
- Code review process
- `mix compile --warnings-as-errors`

## Preconditions
- A developer is creating a new batch of event handlers for a new domain (e.g., Analytics).
- At least one existing `Dashboard*Handlers` module exists as a reference.

## Trigger
A developer needs to handle a new class of events that does not fit in any existing handler module.

## Main Success Flow
1. Developer identifies the domain name for the new handlers (e.g., `Analytics`).
2. Developer creates `lib/observatory_web/live/dashboard_analytics_handlers.ex` with the module name `ObservatoryWeb.DashboardAnalyticsHandlers`.
3. The module defines handler functions that return `socket` (not `{:noreply, socket}`).
4. `dashboard_live.ex` gains `import ObservatoryWeb.DashboardAnalyticsHandlers`.
5. `mix compile --warnings-as-errors` passes with zero warnings.

## Alternate Flows

### A1: New events extend an existing handler module's domain
Condition: The new events fit within the messaging domain.
Steps:
1. Functions are added to `ObservatoryWeb.DashboardMessagingHandlers`.
2. No new module is created.
3. The existing import in `DashboardLive` already covers the new functions.

## Failure Flows

### F1: New handler module uses incorrect naming
Condition: A developer creates `ObservatoryWeb.AnalyticsHelper` instead of `ObservatoryWeb.DashboardAnalyticsHandlers`.
Steps:
1. Code review identifies the non-conforming name.
2. The module is renamed to `ObservatoryWeb.DashboardAnalyticsHandlers`.
3. All references are updated.
4. `mix compile --warnings-as-errors` passes after correction.
Result: Naming convention restored.

### F2: Logic placed directly in DashboardLive instead of new module
Condition: New event handling code is written inline in `dashboard_live.ex`.
Steps:
1. Code review identifies the inline code.
2. The code is extracted to a new appropriately-named handler module.
3. `mix compile --warnings-as-errors` passes.

## Gherkin Scenarios

### S1: New handler module follows Dashboard prefix convention
```gherkin
Scenario: A new handler module for Analytics follows the naming convention
  Given a developer creates a module for analytics event handling
  When the module is defined
  Then its name is ObservatoryWeb.DashboardAnalyticsHandlers
  And it is located at lib/observatory_web/live/dashboard_analytics_handlers.ex
  And mix compile --warnings-as-errors passes
```

### S2: All existing handler modules follow the convention
```gherkin
Scenario: All handler modules imported by DashboardLive follow the naming convention
  Given the current Observatory codebase
  When all imports in dashboard_live.ex are listed
  Then each imported module name matches the pattern ObservatoryWeb.Dashboard*Handlers
```

## Acceptance Criteria
- [ ] `grep -r "^defmodule ObservatoryWeb.Dashboard" lib/observatory_web/live/ | grep -v "Handlers"` returns no output (all handler modules use the `Handlers` suffix) (S1).
- [ ] `grep "import ObservatoryWeb" lib/observatory_web/live/dashboard_live.ex` shows only imports matching the `Dashboard*Handlers` pattern (S2).
- [ ] `mix compile --warnings-as-errors` passes (S1).

## Data
**Inputs:** Domain name for the new handler batch; event names handled
**Outputs:** New `Dashboard{Domain}Handlers` module; import added to `DashboardLive`
**State changes:** Source tree gains a new handler module file; `dashboard_live.ex` gains one import line

## Traceability
- Parent FR: [FR-5.11](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-011](../../decisions/ADR-011-handler-delegation.md)
