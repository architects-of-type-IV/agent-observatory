---
id: UC-0153
title: Enforce five-level hierarchy with no skipped or excess levels
status: draft
parent_fr: FR-6.4
adrs: [ADR-009]
---

# UC-0153: Enforce Five-Level Hierarchy with No Skipped or Excess Levels

## Intent
Roadmap files must use exactly five named levels: Phase (depth 1), Section (depth 2), Story (depth 3), Task (depth 4), Subtask (depth 5). Files must not skip levels (e.g., a Phase containing Tasks without intervening Sections and Stories) and must not exceed depth 5. The dotted prefix depth is the sole indicator of hierarchy level.

## Primary Actor
Agent (team lead designing the roadmap)

## Supporting Actors
- File system (validates via filename inspection)
- Other agents (depend on correct hierarchy for discovery)

## Preconditions
- A roadmap directory exists.
- The lead is decomposing work into a hierarchical breakdown.

## Trigger
The lead creates roadmap files for a new sprint.

## Main Success Flow
1. The lead creates Phase files: `1-setup.md`, `2-implementation.md`.
2. Under Phase 1, the lead creates Section files: `1.1-database.md`, `1.2-api.md`.
3. Under Section 1.1, the lead creates Story files: `1.1.1-schema.md`.
4. Under Story 1.1.1, the lead creates Task files: `1.1.1.1-create-table.md`, `1.1.1.2-add-indexes.md`.
5. If a task requires further decomposition, Subtask files are created: `1.1.1.1.1-define-columns.md`.
6. No file has fewer than 1 or more than 5 dot-separated segments in its prefix.

## Alternate Flows

### A1: Work is simple enough to not need all 5 levels
Condition: A task requires no subtask decomposition.
Steps:
1. Files are created down to the Task level (depth 4) but no Subtask files are needed.
2. The hierarchy terminates at Task level; Subtasks are optional when unnecessary.

## Failure Flows

### F1: Phase file directly contains Tasks (skips Section and Story)
Condition: A file `1.1-create-table.md` is created where the intent was a Task but the prefix suggests a Section (depth 2 = Section, not Task).
Steps:
1. The hierarchy level inferred from the depth-2 prefix is Section, not Task.
2. The file's content indicates it is Task-level work.
3. The naming is corrected: if it is a Task, it needs a 4-level prefix such as `1.1.1.1-create-table.md`.
4. Section `1.1` and Story `1.1.1` files are created as intermediaries.
Result: All five levels are present when the work warrants decomposition.

### F2: File with depth-6 prefix created
Condition: A file `1.1.1.1.1.1-extra.md` has 6 dot-separated segments.
Steps:
1. The file exceeds the maximum hierarchy depth.
2. The excess level is merged into the Subtask level or the work is re-structured.
3. The file is renamed to a maximum depth-5 name.
Result: Hierarchy depth capped at 5.

## Gherkin Scenarios

### S1: All five levels present in a well-formed roadmap
```gherkin
Scenario: A complete roadmap with all five levels compiles structurally
  Given roadmap files 1-setup.md, 1.1-database.md, 1.1.1-schema.md, 1.1.1.1-create-table.md, 1.1.1.1.1-add-index.md
  When an agent inspects the filenames
  Then each file's hierarchy level matches its dotted prefix depth
  And no level is skipped in the chain from Phase to Subtask
```

### S2: No file exceeds depth 5
```gherkin
Scenario: All roadmap files have at most 5 dot-separated prefix segments
  Given all roadmap files in .claude/roadmaps/roadmap-{ts}/
  When their filenames are inspected
  Then no filename prefix contains more than 5 dot-separated integer segments
```

## Acceptance Criteria
- [ ] `ls .claude/roadmaps/roadmap-1771113081/ | awk -F'-' '{print $1}' | tr '.' '\n' | wc -l` for each file returns between 1 and 5 (confirming no file has more than 5 prefix segments) (S2).
- [ ] For each Task file (depth-4 prefix), corresponding Phase, Section, and Story files exist in the same directory (no skipped levels) (S1).
- [ ] No file in the roadmap directory has a prefix with depth 6 or more (S2).

## Data
**Inputs:** Work breakdown structure from the lead; hierarchy level assignments
**Outputs:** Roadmap files with 1-to-5 segment dotted prefixes covering all required levels
**State changes:** File system gains roadmap files; each file's name encodes its hierarchy depth

## Traceability
- Parent FR: [FR-6.4](../frds/FRD-006-roadmap-file-conventions.md)
- ADR: [ADR-009](../../decisions/ADR-009-roadmap-naming.md)
