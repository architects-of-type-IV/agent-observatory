---
id: UC-0155
title: Archive roadmap directory when team is deleted
status: draft
parent_fr: FR-6.6
adrs: [ADR-009]
---

# UC-0155: Archive Roadmap Directory When Team is Deleted

## Intent
When a team is deleted (via `TeamDelete` or the `gc.sh` cleanup script), the active roadmap is moved to `<project-root>/.claude/roadmaps/archived/` retaining its original `roadmap-{ts}` directory name. This preserves the historical record of what was planned and built without keeping the roadmap in the active path.

## Primary Actor
Agent (team lead executing `TeamDelete` or `gc.sh`)

## Supporting Actors
- `gc.sh` script at `~/.claude/skills/dag/scripts/gc.sh`
- File system (`<project-root>/.claude/roadmaps/archived/`)

## Preconditions
- A team is being deleted after all tasks are complete.
- An active roadmap exists at `<project-root>/.claude/roadmaps/roadmap-{ts}/`.
- `<project-root>/.claude/roadmaps/archived/` exists or can be created.

## Trigger
The lead calls `TeamDelete` or the equivalent cleanup.

## Main Success Flow
1. The lead ensures all workers have shut down.
2. The lead (or `gc.sh`) creates `<project-root>/.claude/roadmaps/archived/` if it does not exist.
3. The roadmap directory is moved: `mv .claude/roadmaps/roadmap-{ts}/ .claude/roadmaps/archived/roadmap-{ts}/`.
4. All files within the roadmap are preserved in their original flat structure.
5. The archived directory is readable post-move.

## Alternate Flows

### A1: archived/ directory already exists
Condition: A previous sprint was already archived.
Steps:
1. `archived/` exists.
2. `mv` moves the current roadmap into it alongside previous archives.
3. Both sprint archives coexist with distinct timestamp-based names.

## Failure Flows

### F1: Roadmap is deleted instead of archived
Condition: A developer runs `rm -rf .claude/roadmaps/roadmap-{ts}/` instead of moving it.
Steps:
1. The roadmap content is permanently deleted.
2. Historical record of the sprint's work breakdown is lost.
Result: The `rm` prohibition prevents this; `mv` to `archived/` is the only permitted removal.

### F2: Files are not preserved after move
Condition: The `mv` command fails mid-operation (e.g., disk full).
Steps:
1. Some files may be moved and others may not.
2. The lead manually completes the move of remaining files.
3. All files are verified present in `archived/roadmap-{ts}/`.
Result: Partial moves require manual recovery; disk space should be confirmed before archival.

## Gherkin Scenarios

### S1: Roadmap moved to archived/ on TeamDelete
```gherkin
Scenario: Active roadmap is moved to archived/ directory on TeamDelete
  Given a team has completed all tasks
  And .claude/roadmaps/roadmap-1771113081/ contains 29 files
  When TeamDelete or gc.sh executes
  Then .claude/roadmaps/archived/roadmap-1771113081/ exists
  And it contains the same 29 files
  And .claude/roadmaps/roadmap-1771113081/ no longer exists at the original path
```

### S2: Archived roadmap retains flat structure
```gherkin
Scenario: Archived roadmap files remain flat (no subdirectories added during archival)
  Given .claude/roadmaps/roadmap-1771113081/ contains 29 flat files
  When the roadmap is moved to archived/
  Then ls .claude/roadmaps/archived/roadmap-1771113081/ lists 29 files with no subdirectories
```

## Acceptance Criteria
- [ ] After a `TeamDelete` for the test team, `ls .claude/roadmaps/archived/roadmap-{ts}/` lists all files that were in the active roadmap before deletion (S1).
- [ ] `ls .claude/roadmaps/roadmap-{ts}/` returns "No such file or directory" after archival (S1).
- [ ] `find .claude/roadmaps/archived/roadmap-{ts}/ -type d | wc -l` returns 1 (only the directory itself, no subdirectories) (S2).

## Data
**Inputs:** Active roadmap directory path; `archived/` destination path
**Outputs:** Roadmap directory moved to `<project-root>/.claude/roadmaps/archived/roadmap-{ts}/`
**State changes:** Active roadmap absent from `roadmaps/`; archived copy present in `roadmaps/archived/`

## Traceability
- Parent FR: [FR-6.6](../frds/FRD-006-roadmap-file-conventions.md)
- ADR: [ADR-009](../../decisions/ADR-009-roadmap-naming.md)
