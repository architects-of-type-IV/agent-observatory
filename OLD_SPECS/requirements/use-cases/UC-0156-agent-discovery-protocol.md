---
id: UC-0156
title: Discover and read roadmap files using two-step ls and prefix filter
status: draft
parent_fr: FR-6.7
adrs: [ADR-009]
---

# UC-0156: Discover and Read Roadmap Files Using Two-Step ls and Prefix Filter

## Intent
Agents discover available roadmap files using a two-step protocol: first list the roadmap directory, then filter by dotted prefix to find items at a specific hierarchy level. Agents must not assume subdirectories exist and must not attempt to traverse them. This protocol works because all files are flat in a single directory.

## Primary Actor
Agent (worker reading its task assignment)

## Supporting Actors
- File system (roadmap directory)
- `ls` and `grep` (discovery tools)
- Lead's initial prompt (provides the roadmap timestamp)

## Preconditions
- The agent knows the roadmap timestamp from the lead's initial prompt.
- The roadmap directory exists and is stable.

## Trigger
An agent receives its initial task assignment and needs to find and read its roadmap file.

## Main Success Flow
1. Agent extracts the roadmap timestamp from the lead's prompt (e.g., `1771113081`).
2. Agent lists the directory: `ls .claude/roadmaps/roadmap-1771113081/`.
3. Agent identifies its assigned task ID from the file list (e.g., `2.1.1.1-detect-role.md`).
4. Agent reads the file: `cat .claude/roadmaps/roadmap-1771113081/2.1.1.1-detect-role.md`.
5. Agent proceeds with implementation based on the file content.

## Alternate Flows

### A1: Agent filters by phase prefix to see its scope
Condition: An agent is responsible for all Phase 2 work and needs to enumerate its tasks.
Steps:
1. `ls .claude/roadmaps/roadmap-{ts}/ | grep '^2\.'` lists all Phase 2 items (sections, stories, tasks, subtasks).
2. Agent reads each relevant file to understand the full scope.
3. Agent picks up individual task files as needed.

## Failure Flows

### F1: Agent attempts to traverse a subdirectory
Condition: An agent incorrectly assumes subdirectories exist and calls `ls .claude/roadmaps/roadmap-{ts}/phase-2/`.
Steps:
1. The path does not exist (flat structure has no subdirectories).
2. `ls` returns "No such file or directory".
3. The agent falls back to listing the root directory.
4. The agent uses prefix filtering to find Phase 2 items.
Result: Subdirectory traversal always fails; the flat structure and prefix filter is the correct approach.

### F2: Agent does not know the roadmap timestamp
Condition: The lead's prompt did not include the roadmap timestamp.
Steps:
1. Agent lists `<project-root>/.claude/roadmaps/` to find available roadmap directories.
2. Agent identifies the most recent directory by timestamp ordering (highest number = most recent).
3. Agent proceeds with step 2 of the main flow.

## Gherkin Scenarios

### S1: Agent discovers and reads its assigned task file
```gherkin
Scenario: Agent reads its task from the roadmap using the two-step discovery protocol
  Given the lead's prompt contains roadmap timestamp 1771113081
  And the agent is assigned task 2.1.1.1
  When the agent lists .claude/roadmaps/roadmap-1771113081/
  Then the file 2.1.1.1-detect-role.md is in the listing
  When the agent reads 2.1.1.1-detect-role.md
  Then the task description and acceptance criteria are available
```

### S2: Prefix filter returns only Phase 2 items
```gherkin
Scenario: Prefix filter isolates Phase 2 files
  Given .claude/roadmaps/roadmap-1771113081/ contains files for Phases 1, 2, and 3
  When ls .clone/roadmaps/roadmap-1771113081/ | grep "^2\." is executed
  Then only Phase 2 files are returned
  And no Phase 1 or Phase 3 files appear in the output
```

### S3: Subdirectory traversal attempt fails gracefully
```gherkin
Scenario: Attempting ls on a non-existent subdirectory returns an error
  Given .claude/roadmaps/roadmap-1771113081/ has a flat structure
  When ls .claude/roadmaps/roadmap-1771113081/phase-2/ is executed
  Then ls returns "No such file or directory"
  And the agent falls back to listing the root roadmap directory
```

## Acceptance Criteria
- [ ] A test script running `ls .claude/roadmaps/roadmap-1771113081/` returns a list of `.md` files with no directories (S1).
- [ ] `ls .claude/roadmaps/roadmap-1771113081/ | grep '^2\.'` returns only files beginning with `2.` (S2).
- [ ] `ls .claude/roadmaps/roadmap-1771113081/phase-1/ 2>&1` includes "No such file or directory" (confirming no subdirectory exists) (S3).

## Data
**Inputs:** Roadmap timestamp from lead's prompt; assigned task ID (dotted prefix)
**Outputs:** Task file contents read by agent; implementation proceeds based on task spec
**State changes:** No state changes; read-only discovery

## Traceability
- Parent FR: [FR-6.7](../frds/FRD-006-roadmap-file-conventions.md)
- ADR: [ADR-009](../../decisions/ADR-009-roadmap-naming.md)
