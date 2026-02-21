---
id: UC-0157
title: Use Unix epoch timestamp as roadmap ID with no coordination
status: draft
parent_fr: FR-6.8
adrs: [ADR-009]
---

# UC-0157: Use Unix Epoch Timestamp as Roadmap ID with No Coordination

## Intent
Roadmap IDs are Unix epoch integers obtained at the moment of directory creation (`date +%s` or `System.os_time(:second)`). Using the wall-clock timestamp eliminates the need for any coordination mechanism to assign the next available ID. Multiple roadmaps created on the same day each receive unique IDs because they are created at different seconds.

## Primary Actor
Agent (team lead or developer creating the roadmap)

## Supporting Actors
- `date +%s` shell command or `System.os_time(:second)` Elixir call
- File system

## Preconditions
- The lead is about to create a new roadmap directory.
- The system clock is accurate.

## Trigger
The lead executes the roadmap creation step at the start of a new sprint.

## Main Success Flow
1. Lead calls `date +%s` and receives the current Unix timestamp (e.g., `1771200000`).
2. Lead creates the directory: `mkdir .claude/roadmaps/roadmap-1771200000/`.
3. The timestamp value is unique because it is taken at the exact creation second.
4. No lock file, counter file, or shared state is needed.
5. Roadmaps are naturally ordered by timestamp when listed with `ls .claude/roadmaps/ | sort`.

## Alternate Flows

### A1: Two roadmaps created within the same second
Condition: Two leads independently create roadmaps at the same second (edge case).
Steps:
1. Both `date +%s` calls return the same value.
2. The second `mkdir` fails because the directory already exists.
3. One lead retries with the next second's timestamp.
Result: The collision is detected immediately via `mkdir` failure; no silent conflict.

## Failure Flows

### F1: Auto-incrementing integer used as roadmap ID
Condition: A lead creates `.claude/roadmaps/roadmap-001/` using a counter.
Steps:
1. The next sprint requires a shared counter or manual inspection to determine the next available ID.
2. Two agents independently creating roadmaps may pick the same counter value.
3. The directory is renamed to a Unix timestamp.
Result: Auto-incrementing IDs introduce coordination overhead that timestamps eliminate.

### F2: Slug used as roadmap ID
Condition: A lead creates `.claude/roadmaps/roadmap-feature-auth/`.
Steps:
1. The slug is human-readable but requires manual de-confliction.
2. Chronological ordering is impossible from the name alone.
3. The directory is renamed to a Unix timestamp.
Result: Slug IDs break chronological sorting; timestamps are required.

## Gherkin Scenarios

### S1: Roadmap ID is a decimal Unix timestamp
```gherkin
Scenario: Roadmap directory name is a Unix epoch timestamp
  Given the lead runs date +%s which returns 1771200000
  When the lead creates the roadmap directory
  Then it is named .claude/roadmaps/roadmap-1771200000/
  And the timestamp 1771200000 is a decimal integer with no padding or leading zeros
```

### S2: ls .claude/roadmaps/ | sort shows roadmaps in chronological order
```gherkin
Scenario: Roadmaps are sortable chronologically by directory name
  Given three roadmaps with timestamps 1771100000, 1771150000, and 1771200000
  When ls .claude/roadmaps/ | sort is executed
  Then roadmap-1771100000/ appears first
  And roadmap-1771200000/ appears last
```

## Acceptance Criteria
- [ ] Every roadmap directory in `.claude/roadmaps/` (excluding `archived/`) has a name matching `roadmap-[0-9]{10}/` (10-digit Unix timestamp) (S1).
- [ ] `ls .claude/roadmaps/ | sort` lists roadmaps in chronological creation order (S2).
- [ ] No roadmap directory name contains a slash, underscore, letter prefix, or leading zeros in the numeric part (S1).

## Data
**Inputs:** Current Unix timestamp from `date +%s` at creation time
**Outputs:** Roadmap directory named `roadmap-{N}/` where N is a 10-digit Unix timestamp
**State changes:** File system gains the new roadmap directory with its unique timestamp name

## Traceability
- Parent FR: [FR-6.8](../frds/FRD-006-roadmap-file-conventions.md)
- ADR: [ADR-009](../../decisions/ADR-009-roadmap-naming.md)
