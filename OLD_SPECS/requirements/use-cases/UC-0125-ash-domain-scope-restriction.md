---
id: UC-0125
title: Reject new Ash domains for ephemeral coordination data
status: draft
parent_fr: FR-5.1
adrs: [ADR-006]
---

# UC-0125: Reject New Ash Domains for Ephemeral Coordination Data

## Intent
The codebase enforces a three-domain ceiling for Ash: `Events`, `AgentTools`, and `Costs`. Any proposal to introduce a new Ash domain for ephemeral data (messages, tasks, real-time annotations) is rejected at code review and replaced with a plain GenServer/ETS module. This constraint is verified by checking the source tree for unexpected domain modules.

## Primary Actor
Developer

## Supporting Actors
- Code review process
- `mix compile --warnings-as-errors` (compile-time enforcement via `use Ash.Domain` presence check)
- `Observatory.Mailbox`, `Observatory.SwarmMonitor`, `Observatory.Notes` (canonical plain-module alternatives)

## Preconditions
- A developer is about to introduce new data handling code for coordination data (agent messages, task pipeline state, annotations).
- The three existing Ash domains (`Events`, `AgentTools`, `Costs`) are present and compiling cleanly.

## Trigger
A developer creates or proposes a new Elixir module that uses `use Ash.Domain` for ephemeral coordination data.

## Main Success Flow
1. The developer consults the architecture rules and identifies the data as ephemeral (no persistence requirement, no query API needed, real-time access pattern).
2. The developer selects a plain GenServer with ETS as the implementation, following the canonical pattern of `Observatory.Mailbox`.
3. The new module is created as a plain GenServer in `lib/observatory/`.
4. `mix compile --warnings-as-errors` passes with zero warnings.
5. The three Ash domains remain the only modules with `use Ash.Domain` in the codebase.

## Alternate Flows

### A1: Data is persistent and queryable (appropriate for Ash)
Condition: The data requires SQL persistence, Ash policy auth, or an API surface.
Steps:
1. The developer verifies the use case genuinely fits one of the three existing domains or warrants a fourth.
2. If a new domain is justified, it is added to one of the three existing domains as a new resource, not as a standalone new domain.
3. `mix compile --warnings-as-errors` passes.

## Failure Flows

### F1: New Ash domain created for ephemeral data
Condition: A new module containing `use Ash.Domain` is committed for ephemeral coordination data.
Steps:
1. The module is identified during code review by grep: `grep -r "use Ash.Domain" lib/`.
2. The module is moved to `tmp/trash/` (not deleted with `rm`).
3. A plain GenServer replacement is implemented.
4. `mix compile --warnings-as-errors` passes after removal.
Result: Dead domain eliminated; plain module pattern restored.

## Gherkin Scenarios

### S1: Only three Ash domains exist in the lib directory
```gherkin
Scenario: The codebase contains exactly three modules using use Ash.Domain
  Given the Observatory codebase is in a known-good state
  When grep -r "use Ash.Domain" lib/ is executed
  Then the output contains exactly three files: observatory/events.ex, observatory/agent_tools.ex, observatory/costs.ex
```

### S2: New ephemeral module uses plain GenServer not Ash Domain
```gherkin
Scenario: A developer implements message routing as a plain GenServer
  Given a requirement to store and route agent messages
  When the implementation is reviewed
  Then the module uses GenServer.start_link and :ets.new rather than use Ash.Domain
  And mix compile --warnings-as-errors passes with zero warnings
```

### S3: Mistakenly created Ash domain is moved to trash not rm'd
```gherkin
Scenario: Dead Ash domain is soft-deleted to tmp/trash/
  Given a module Observatory.Messaging exists with use Ash.Domain
  And it is identified as dead code handling ephemeral data
  When the module is removed
  Then the file is moved to tmp/trash/ not deleted with rm
  And mix compile --warnings-as-errors passes after removal
```

## Acceptance Criteria
- [ ] `grep -r "use Ash.Domain" lib/` in the Observatory project returns exactly 3 results matching the three authorised domains (S1).
- [ ] No module in `lib/observatory/` contains `use Ash.Domain` except `events.ex`, `agent_tools.ex`, and `costs.ex` (S1).
- [ ] `mix compile --warnings-as-errors` passes with the current domain set (S2).

## Data
**Inputs:** Proposed module code; `use Ash.Domain` presence as signal
**Outputs:** Either a plain GenServer module or a new resource added to an existing domain
**State changes:** `lib/` tree does not gain a new `use Ash.Domain` module; any dead domain moved to `tmp/trash/`

## Traceability
- Parent FR: [FR-5.1](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-006](../../decisions/ADR-006-dead-ash-domains.md)
