---
id: UC-0150
title: Create roadmap directory at project root with Unix timestamp ID
status: draft
parent_fr: FR-6.1
adrs: [ADR-009]
---

# UC-0150: Create Roadmap Directory at Project Root with Unix Timestamp ID

## Intent
When a new multi-agent team sprint begins, the lead creates a roadmap directory at `<project-root>/.claude/roadmaps/roadmap-{unix-timestamp}/`. The timestamp is taken at creation time using `date +%s`, guaranteeing a unique, chronologically sortable directory name without coordination overhead.

## Primary Actor
Agent (team lead or developer initiating the sprint)

## Supporting Actors
- File system at `<project-root>/.claude/roadmaps/`
- `date +%s` shell command (or `System.os_time(:second)` in Elixir)

## Preconditions
- The project root exists and is writable.
- No roadmap exists for the current sprint (a new one is needed).

## Trigger
The lead receives an instruction to start a new team sprint and begin roadmap creation.

## Main Success Flow
1. The lead checks whether `<project-root>/.claude/roadmaps/` exists; if not, it is created.
2. The current Unix timestamp is obtained: `date +%s` returns e.g. `1771200000`.
3. The roadmap directory is created: `mkdir <project-root>/.claude/roadmaps/roadmap-1771200000/`.
4. The directory is empty; no subdirectories are created inside it.
5. The lead informs all workers of the roadmap timestamp so they can locate files.

## Alternate Flows

### A1: Parent .claude/roadmaps/ directory does not exist
Condition: The `.claude/roadmaps/` parent has not been created yet.
Steps:
1. `mkdir -p <project-root>/.claude/roadmaps/roadmap-{ts}/` creates both parent and roadmap directory.
2. All subsequent roadmap files for this sprint are placed flat in the new directory.

## Failure Flows

### F1: Slug-based name used instead of timestamp
Condition: The lead creates `.claude/roadmaps/roadmap-feature-auth/` using a descriptive slug.
Steps:
1. The directory exists but is not chronologically sortable by name.
2. Cross-referencing with other roadmaps by time requires inspecting file metadata.
3. The directory is renamed to the correct timestamp format.
4. Workers are notified of the correct path.
Result: Slug-based names violate the convention and must be corrected.

### F2: Auto-incrementing integer used instead of timestamp
Condition: The lead creates `.claude/roadmaps/roadmap-001/`.
Steps:
1. A coordination mechanism would be required to determine the next available integer.
2. The directory is renamed to a Unix timestamp name.
Result: Auto-incrementing IDs introduce coordination overhead that timestamps avoid.

## Gherkin Scenarios

### S1: Roadmap directory created with Unix timestamp name
```gherkin
Scenario: Lead creates a roadmap directory using a Unix timestamp
  Given the project root is /Users/xander/code/www/kardashev/observatory
  And date +%s returns 1771200000
  When the lead creates the roadmap directory
  Then the directory .claude/roadmaps/roadmap-1771200000/ exists
  And ls .claude/roadmaps/roadmap-1771200000/ returns no entries (empty directory)
  And no subdirectories exist inside it
```

### S2: Multiple roadmaps on the same day each get unique timestamps
```gherkin
Scenario: Two roadmaps created the same day each have distinct timestamp names
  Given two roadmaps are created on 2026-02-21 at different times
  When ls .claude/roadmaps/ is run
  Then two directories exist: roadmap-{ts1}/ and roadmap-{ts2}/ where ts1 != ts2
  And the later directory has a higher timestamp value
```

## Acceptance Criteria
- [ ] `ls .claude/roadmaps/` in the Observatory project lists only directories matching `roadmap-[0-9]+/` (no slug names, no integer-sequence names) (S1).
- [ ] Each roadmap directory name is a valid Unix timestamp (value between 1,000,000,000 and 9,999,999,999) (S1).
- [ ] `ls .claude/roadmaps/roadmap-{ts}/` returns no subdirectories (S1).

## Data
**Inputs:** Current Unix timestamp from `date +%s`; project root path
**Outputs:** Directory at `<project-root>/.claude/roadmaps/roadmap-{ts}/`
**State changes:** File system gains the roadmap directory; `.claude/roadmaps/` parent created if absent

## Traceability
- Parent FR: [FR-6.1](../frds/FRD-006-roadmap-file-conventions.md)
- ADR: [ADR-009](../../decisions/ADR-009-roadmap-naming.md)
