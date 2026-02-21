---
id: UC-0152
title: Name roadmap files with dotted hierarchical prefix and kebab slug
status: draft
parent_fr: FR-6.3
adrs: [ADR-009]
---

# UC-0152: Name Roadmap Files with Dotted Hierarchical Prefix and Kebab Slug

## Intent
Every roadmap file is named with a dotted prefix that encodes its position in the 5-level hierarchy, followed by a hyphen and a lowercase kebab-case slug, and ending with `.md`. The number of dot-separated segments indicates the hierarchy level (1 = Phase, 2 = Section, 3 = Story, 4 = Task, 5 = Subtask). This naming enables prefix-based filtering with `ls | grep '^N\.'` without any directory traversal.

## Primary Actor
Agent (team lead or worker creating a roadmap file)

## Supporting Actors
- File system
- `ls` and `grep` commands for discovery

## Preconditions
- A roadmap directory exists at `<project-root>/.claude/roadmaps/roadmap-{ts}/`.
- The lead has assigned a hierarchy position to the new file.

## Trigger
The lead or a worker is creating a new roadmap file for a specific hierarchy node.

## Main Success Flow
1. The lead determines the hierarchy level and position: Phase 2, Section 1, Story 1, Task 1 → `2.1.1.1`.
2. The lead chooses a descriptive slug: `detect-role`.
3. The filename is composed: `2.1.1.1-detect-role.md`.
4. The file is created at `.claude/roadmaps/roadmap-{ts}/2.1.1.1-detect-role.md`.
5. Running `ls .claude/roadmaps/roadmap-{ts}/ | grep '^2\.'` lists all Phase 2 items including this file.

## Alternate Flows

### A1: Listing items at a specific section level
Condition: An agent needs all Section 1.1 items.
Steps:
1. `ls .claude/roadmaps/roadmap-{ts}/ | grep '^1\.1\.'` returns all Stories, Tasks, and Subtasks under Section 1.1.
2. Filtering by `'^1\.1\.1'` narrows to Story 1.1.1 and below.

## Failure Flows

### F1: File named without dotted prefix
Condition: A file is named `detect-role.md` with no dotted prefix.
Steps:
1. The file is visible in `ls` but cannot be filtered by hierarchy prefix.
2. The file's position in the hierarchy is ambiguous.
3. The file is renamed to the correct dotted form (e.g., `2.1.1.1-detect-role.md`).
Result: Hierarchy recovery requires manual inspection and renaming.

### F2: Underscores used instead of dots in prefix
Condition: A file is named `2_1_1_1-detect-role.md`.
Steps:
1. Prefix-based filtering (`grep '^2\.'`) does not match.
2. The file is renamed using dots: `2.1.1.1-detect-role.md`.
Result: Dot separator is mandatory.

## Gherkin Scenarios

### S1: Task file named with 4-level dotted prefix
```gherkin
Scenario: A Task file is named with a 4-segment dotted prefix
  Given a Task at Phase 2, Section 1, Story 1, position 1
  When the file is created
  Then it is named 2.1.1.1-detect-role.md
  And ls .claude/roadmaps/roadmap-{ts}/ | grep "^2\." includes this file
```

### S2: Phase file named with 1-segment prefix
```gherkin
Scenario: A Phase file has a single-segment dotted prefix
  Given Phase 1 needs a file
  When the file is created
  Then it is named 1-setup.md
  And ls | grep "^1-" returns this file
```

### S3: Files at different levels are distinguishable by prefix depth
```gherkin
Scenario: Hierarchy level is inferrable from the number of dot-separated segments in the prefix
  Given files 1-setup.md, 1.1-database.md, 1.1.1-schema.md, 1.1.1.1-create-table.md
  When an agent reads the filenames
  Then 1-setup.md is identified as a Phase (depth 1)
  And 1.1-database.md is identified as a Section (depth 2)
  And 1.1.1-schema.md is identified as a Story (depth 3)
  And 1.1.1.1-create-table.md is identified as a Task (depth 4)
```

## Acceptance Criteria
- [ ] `ls .claude/roadmaps/roadmap-1771113081/` shows all files with names matching the regex `^[0-9]+(\.[0-9]+)*-[a-z][a-z0-9-]*\.md$` (S1, S2).
- [ ] No file in any roadmap directory uses underscores in the dotted prefix (S1).
- [ ] `ls .claude/roadmaps/roadmap-{ts}/ | grep '^2\.'` returns all Phase 2 items and only Phase 2 items (S3).

## Data
**Inputs:** Hierarchy level and position integers; descriptive slug; roadmap directory path
**Outputs:** File at `roadmap-{ts}/N.N.N-slug.md` with correct naming
**State changes:** File system gains one new roadmap file with a correctly named path

## Traceability
- Parent FR: [FR-6.3](../frds/FRD-006-roadmap-file-conventions.md)
- ADR: [ADR-009](../../decisions/ADR-009-roadmap-naming.md)
