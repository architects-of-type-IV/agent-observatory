---
id: UC-0133
title: Use sed for in-place edits on files with active format-on-save hooks
status: draft
parent_fr: FR-5.9
adrs: [ADR-010]
---

# UC-0133: Use sed for In-Place Edits on Files with Active Format-on-Save Hooks

## Intent
Files that have editor format-on-save hooks active can be corrupted by the Edit tool's read-then-write sequence if the hook fires between the read and write steps. Using `sed -i ''` for targeted in-place substitutions bypasses this race condition because the substitution and write are atomic from the operating system's perspective.

## Primary Actor
Developer

## Supporting Actors
- `sed -i ''` (BSD sed in-place substitution)
- Editor format-on-save hook (e.g., `mix format`)
- `mix compile --warnings-as-errors` (post-edit verification)

## Preconditions
- A component file (e.g., `feed_components.ex`) has an active format-on-save hook in the developer's editor.
- A targeted substitution needs to be applied (e.g., rename a function across the file).

## Trigger
A developer or agent applies a targeted edit to a source file that has format-on-save active.

## Main Success Flow
1. Developer identifies the need to rename `old_function` to `new_function` across a file.
2. Developer runs: `sed -i '' 's/old_function/new_function/g' lib/observatory_web/components/feed_components.ex`.
3. The substitution is applied atomically.
4. The format-on-save hook fires after the `sed` write, not during a read-write gap.
5. `mix compile --warnings-as-errors` passes with zero warnings.

## Alternate Flows

### A1: Edit tool used on a file without active format hooks
Condition: The target file does not have a format-on-save hook configured.
Steps:
1. The Edit tool performs the standard read-then-write sequence safely.
2. No race condition occurs.
3. `mix compile --warnings-as-errors` passes.

## Failure Flows

### F1: Edit tool used on a file with active format hook
Condition: The Edit tool reads `feed_components.ex`; the format hook fires and modifies the file; the Edit tool writes its diff.
Steps:
1. The Edit tool's write contains content from before the hook fired.
2. The file is corrupted or the edit is partially applied.
3. `mix compile --warnings-as-errors` may fail with a syntax error.
4. Developer runs `git checkout -- lib/observatory_web/components/feed_components.ex` to restore.
5. Developer re-applies the change using `sed -i ''`.
Result: File restored; correct edit applied without race condition.

## Gherkin Scenarios

### S1: sed rename succeeds without race condition
```gherkin
Scenario: sed -i '' renames a function across a file atomically
  Given feed_components.ex has an active format-on-save hook
  And the file contains occurrences of "old_function"
  When sed -i '' 's/old_function/new_function/g' is run on the file
  Then all occurrences are replaced with "new_function"
  And mix compile --warnings-as-errors passes with zero warnings
  And no stale-content corruption occurs
```

### S2: Edit tool on format-hook file causes stale-content error
```gherkin
Scenario: Edit tool on a format-hook file produces corruption when hook fires between read and write
  Given feed_components.ex has an active format-on-save hook
  When the Edit tool reads the file and the hook fires before the write
  And the Edit tool applies its write with stale content
  Then the file contains incorrect content or a syntax error
  And mix compile --warnings-as-errors fails
```

## Acceptance Criteria
- [ ] Running `sed -i '' 's/segment_color/event_color/g' lib/observatory_web/components/feed_components.ex` followed by `mix compile --warnings-as-errors` succeeds in a test environment with format hooks active (S1).
- [ ] Project coding guidelines (CLAUDE.md) document that `sed -i ''` is the required approach for files with format-on-save hooks (process criterion, not a code test).

## Data
**Inputs:** Target file path; old string; new string; file with potential format-on-save hook active
**Outputs:** File with substitution applied; no corruption from hook timing
**State changes:** File content updated; format hook may reformat after `sed` write

## Traceability
- Parent FR: [FR-5.9](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-010](../../decisions/ADR-010-component-file-split.md)
