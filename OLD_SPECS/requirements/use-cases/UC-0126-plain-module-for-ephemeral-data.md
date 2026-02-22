---
id: UC-0126
title: Implement ephemeral coordination data as GenServer with ETS
status: draft
parent_fr: FR-5.2
adrs: [ADR-006]
---

# UC-0126: Implement Ephemeral Coordination Data as GenServer with ETS

## Intent
When a new data-handling need arises for real-time, non-persistent coordination data, the developer implements it as a plain GenServer backed by an ETS table, following the canonical pattern established by `Observatory.Mailbox`. Replacing any of the three canonical plain modules with Ash resources is explicitly prohibited.

## Primary Actor
Developer

## Supporting Actors
- `Observatory.Mailbox` (canonical reference implementation)
- `Observatory.SwarmMonitor` (second canonical reference)
- `Observatory.Notes` (third canonical reference)
- ETS (`:ets.new/2`)

## Preconditions
- A new ephemeral data requirement exists (e.g., caching agent annotations in memory).
- The developer has confirmed the data does not require SQL persistence or Ash policy auth.

## Trigger
A developer begins implementing a new real-time coordination module.

## Main Success Flow
1. The developer creates a new module in `lib/observatory/` using `use GenServer`.
2. `init/1` creates an ETS table with appropriate options (`[:named_table, :public, :set]` or similar).
3. The module exposes a client API using `GenServer.call/2` or `GenServer.cast/2`.
4. The module is added to `Observatory.Application` children list.
5. `mix compile --warnings-as-errors` passes with zero warnings.
6. No `use Ash.Domain` or `use Ash.Resource` appears in the module.

## Alternate Flows

### A1: Existing canonical module is extended
Condition: The new requirement fits within an existing plain module (e.g., adding a new Mailbox feature).
Steps:
1. The developer adds a function and ETS operation to the existing module.
2. No new module is created.
3. The module stays under 300 lines; if it would exceed that, a sub-module is created.

## Failure Flows

### F1: Attempt to replace Observatory.Mailbox with an Ash resource
Condition: A developer proposes an `Ash.Resource` for `Message` to replace `Observatory.Mailbox`.
Steps:
1. Code review identifies the `use Ash.Resource` import.
2. The resource module is moved to `tmp/trash/`.
3. `Observatory.Mailbox` (the GenServer) is restored as the canonical implementation.
4. `mix compile --warnings-as-errors` passes after removal.
Result: Plain module pattern restored.

## Gherkin Scenarios

### S1: New ephemeral module compiles clean as GenServer
```gherkin
Scenario: A new plain GenServer module compiles with no warnings
  Given a new module Observatory.AgentNotes is created using GenServer
  And it creates an ETS table in init/1
  And it is added to Observatory.Application children
  When mix compile --warnings-as-errors runs
  Then compilation succeeds with zero warnings
  And Observatory.AgentNotes does not use Ash.Domain or Ash.Resource
```

### S2: Observatory.Mailbox is never replaced with an Ash resource
```gherkin
Scenario: Observatory.Mailbox remains a GenServer after any refactor
  Given the current Observatory codebase
  When grep -r "use Ash.Resource" lib/observatory/mailbox.ex is executed
  Then the command returns no output
  And Observatory.Mailbox uses GenServer
```

## Acceptance Criteria
- [ ] `grep -r "use Ash.Resource" lib/observatory/mailbox.ex lib/observatory/swarm_monitor.ex lib/observatory/notes.ex` returns no output (S2).
- [ ] Each of the three canonical plain modules (`Mailbox`, `SwarmMonitor`, `Notes`) is present in the `Observatory.Application` children list (S1).
- [ ] `mix compile --warnings-as-errors` passes (S1).

## Data
**Inputs:** New requirement description; determination that data is ephemeral
**Outputs:** New GenServer module in `lib/observatory/`; ETS table registered at startup
**State changes:** `Observatory.Application` gains a new supervised child; ETS table created on startup

## Traceability
- Parent FR: [FR-5.2](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-006](../../decisions/ADR-006-dead-ash-domains.md)
