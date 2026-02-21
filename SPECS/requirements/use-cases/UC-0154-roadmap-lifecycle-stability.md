---
id: UC-0154
title: Keep active roadmap files stable during a team session
status: draft
parent_fr: FR-6.5
adrs: [ADR-009]
---

# UC-0154: Keep Active Roadmap Files Stable During a Team Session

## Intent
An active roadmap directory must not be moved, renamed, or structurally modified while agents are reading it. Agents cache the roadmap path from the lead's initial prompt and read files at any time. Relocating or reorganising files mid-session causes missing-file errors in workers that held the original path.

## Primary Actor
Agent (team lead)

## Supporting Actors
- Worker agents (hold cached roadmap directory path)
- File system

## Preconditions
- A team session is in progress with at least one worker reading roadmap files.
- The roadmap directory is at `<project-root>/.claude/roadmaps/roadmap-{ts}/`.

## Trigger
A lead or developer considers reorganising the roadmap directory during an active session.

## Main Success Flow
1. Workers read roadmap files at `<project-root>/.claude/roadmaps/roadmap-{ts}/{file}.md` throughout the session.
2. The lead does not move, rename, or delete any files in the directory during the session.
3. All file reads by workers succeed throughout the session.
4. New files may be added to the directory during the session (adding is safe; restructuring is not).

## Alternate Flows

### A1: New files added mid-session
Condition: The lead identifies additional tasks and creates new roadmap files during the session.
Steps:
1. New files are placed directly in the existing roadmap directory.
2. Workers can discover new files by re-listing the directory.
3. No existing file paths change; no worker encounters a missing-file error.

## Failure Flows

### F1: Lead relocates roadmap files mid-session
Condition: The lead moves files from `roadmap-{ts}/` to a new directory structure.
Steps:
1. Worker agents that have cached the original paths attempt to read files.
2. File reads fail with "no such file or directory".
3. Workers are unable to proceed and must be notified of the new paths.
4. The disruption requires manual intervention to re-orient all workers.
Result: Session disruption; avoid by never relocating active roadmap files.

## Gherkin Scenarios

### S1: Workers successfully read files throughout the session
```gherkin
Scenario: All roadmap files remain accessible throughout the team session
  Given a team session is active with roadmap at .claude/roadmaps/roadmap-1771113081/
  And worker agents have cached this path from the initial prompt
  When workers read task files at any point during the session
  Then all file reads succeed without missing-file errors
  And the roadmap directory structure is unchanged from session start
```

### S2: Adding new files does not disrupt existing file reads
```gherkin
Scenario: Adding new roadmap files mid-session does not affect existing paths
  Given workers are reading files from .claude/roadmaps/roadmap-1771113081/
  When the lead adds a new file 3.2.1.1-new-task.md to the directory
  Then existing files remain at their original paths
  And workers that list the directory can discover the new file
  And no worker encounters a missing-file error
```

## Acceptance Criteria
- [ ] No `mv` or `rename` command is executed on files within an active roadmap directory during a team session (verified by session audit log or CLAUDE.md protocol adherence).
- [ ] All worker agents in a team session can read their assigned roadmap files from start to finish without path errors (S1).
- [ ] New files added to the active roadmap directory are discoverable by workers via `ls` (S2).

## Data
**Inputs:** Active roadmap directory path; file contents
**Outputs:** Stable file paths accessible to all workers throughout the session
**State changes:** Files may be added but never relocated; directory structure is append-only during an active session

## Traceability
- Parent FR: [FR-6.5](../frds/FRD-006-roadmap-file-conventions.md)
- ADR: [ADR-009](../../decisions/ADR-009-roadmap-naming.md)
