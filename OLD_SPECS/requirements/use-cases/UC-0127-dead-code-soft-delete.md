---
id: UC-0127
title: Soft-delete unused modules to tmp/trash instead of rm
status: draft
parent_fr: FR-5.3
adrs: [ADR-006]
---

# UC-0127: Soft-Delete Unused Modules to tmp/trash Instead of rm

## Intent
When a module is identified as dead code (not connected to any real data flow or reachable from the application), it is moved to `<project-root>/tmp/trash/` rather than deleted with `rm`. This preserves audit history and allows recovery. After the move, `mix compile --warnings-as-errors` must pass with zero warnings, confirming the module is no longer referenced.

## Primary Actor
Developer

## Supporting Actors
- File system (`tmp/trash/` directory)
- `mix compile --warnings-as-errors` (verification gate)

## Preconditions
- A module has been identified as dead code (not referenced from any live module or application callback).
- `tmp/trash/` exists or can be created at the project root.

## Trigger
Code review or audit identifies an unused module. The developer proceeds with soft deletion.

## Main Success Flow
1. Developer creates `tmp/trash/` if it does not exist (e.g., `tmp/trash/dead-code-audit/`).
2. Developer moves the file: `mv lib/observatory/dead_module.ex tmp/trash/dead-code-audit/`.
3. Any references to the module in other files are removed or updated.
4. `mix compile --warnings-as-errors` is run.
5. Compilation succeeds with zero warnings.
6. The file remains accessible in `tmp/trash/` for historical review.

## Alternate Flows

### A1: Module is referenced by a live module
Condition: The dead module has callers that import or alias it.
Steps:
1. All callers are updated to remove the reference before the file is moved.
2. After updating callers, the file is moved.
3. `mix compile --warnings-as-errors` confirms zero warnings.

## Failure Flows

### F1: Module deleted with rm instead of moved
Condition: `rm lib/observatory/dead_module.ex` is executed.
Steps:
1. The file is permanently deleted with no recovery path.
2. Git history preserves the content but recovery requires a git checkout.
Result: This violates the project `rm` prohibition. `mv` to `tmp/trash/` is the only permitted removal.

### F2: Module moved but references remain
Condition: Another module still imports or aliases the moved module.
Steps:
1. `mix compile --warnings-as-errors` produces a compilation error.
2. The developer removes the stale reference.
3. Compilation is re-run until it passes clean.
Result: Zero-warnings requirement catches dangling references.

## Gherkin Scenarios

### S1: Dead module moved to tmp/trash and compile passes
```gherkin
Scenario: Unused module is soft-deleted and compilation passes
  Given Observatory.TaskBoard is identified as dead code
  And tmp/trash/ exists at the project root
  When the file is moved to tmp/trash/dead-code-audit/task_board.ex
  And any references to Observatory.TaskBoard are removed
  Then mix compile --warnings-as-errors succeeds with zero warnings
  And the file is readable at tmp/trash/dead-code-audit/task_board.ex
```

### S2: rm is never used to remove module files
```gherkin
Scenario: rm is not used for module file removal
  Given a dead module is identified
  When the developer removes it
  Then the file is present in tmp/trash/ (not permanently deleted)
  And git status shows no deleted files, only moved files
```

## Acceptance Criteria
- [ ] `find tmp/trash/ -name "*.ex" 2>/dev/null` lists previously moved modules (confirms soft-delete pattern is in use) (S1).
- [ ] `mix compile --warnings-as-errors` passes after any soft-delete operation (S1).
- [ ] No module removal in git history uses `git rm` or shell `rm` on `.ex` source files (S2).

## Data
**Inputs:** Path to dead module file; list of modules referencing it
**Outputs:** File at `tmp/trash/<category>/<filename>`; updated callers with stale references removed
**State changes:** `lib/` tree loses the file; `tmp/trash/` gains it; `mix compile` output becomes warning-free

## Traceability
- Parent FR: [FR-5.3](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-006](../../decisions/ADR-006-dead-ash-domains.md)
