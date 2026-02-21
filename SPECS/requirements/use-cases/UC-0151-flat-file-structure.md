---
id: UC-0151
title: Place all roadmap files flat in one directory with no subdirectories
status: draft
parent_fr: FR-6.2
adrs: [ADR-009]
---

# UC-0151: Place All Roadmap Files Flat in One Directory with No Subdirectories

## Intent
All roadmap files for a sprint reside directly inside `<project-root>/.claude/roadmaps/roadmap-{ts}/`. No subdirectories are created inside the roadmap directory under any circumstances. This constraint enables any agent to enumerate the full roadmap with a single `ls` command and filter by dotted prefix without directory traversal.

## Primary Actor
Agent (team lead or worker)

## Supporting Actors
- File system
- `ls` command (agent discovery tool)

## Preconditions
- A roadmap directory exists at `<project-root>/.claude/roadmaps/roadmap-{ts}/`.

## Trigger
An agent or lead creates a new roadmap file or adds content to an existing sprint.

## Main Success Flow
1. The lead creates a new roadmap file directly in the roadmap directory: `touch .claude/roadmaps/roadmap-1771200000/1.1.1-schema.md`.
2. The file is immediately listable: `ls .claude/roadmaps/roadmap-1771200000/` shows it.
3. No subdirectory is created, regardless of how many files exist.
4. Even with 29 files, `ls` shows all 29 at the top level.

## Alternate Flows

### A1: Many files in the same roadmap directory
Condition: A large sprint produces 29 roadmap files covering 5 phases.
Steps:
1. All 29 files are placed directly in the roadmap directory.
2. `ls .claude/roadmaps/roadmap-{ts}/` lists all 29 files.
3. No phase subdirectories (e.g., `phase-1/`, `phase-2/`) are created.

## Failure Flows

### F1: Subdirectory created inside roadmap directory
Condition: An agent or developer creates `.claude/roadmaps/roadmap-{ts}/phase-1/1.1-auth.md`.
Steps:
1. The subdirectory violates the flat structure constraint.
2. The file is moved to the root of the roadmap directory and renamed to include the hierarchy in its dotted prefix (e.g., `1.1-auth.md` if it is a Section file).
3. The subdirectory is removed.
Result: The flat structure is restored. This is the most common violation and must never happen.

## Gherkin Scenarios

### S1: All files in a roadmap directory are at top level
```gherkin
Scenario: A 29-file roadmap has all files at the top level
  Given a roadmap directory .claude/roadmaps/roadmap-1771113081/ with 29 files
  When ls .claude/roadmaps/roadmap-1771113081/ is executed
  Then exactly 29 entries are listed
  And none of the entries is a directory
```

### S2: Attempting to create a subdirectory violates the constraint
```gherkin
Scenario: A subdirectory inside a roadmap directory is detected and corrected
  Given an agent creates .claude/roadmaps/roadmap-1771113081/phase-1/1.1-auth.md
  When the directory structure is inspected
  Then .claude/roadmaps/roadmap-1771113081/phase-1/ is identified as a violation
  And the file is moved to .claude/roadmaps/roadmap-1771113081/1.1-auth.md
  And the phase-1/ subdirectory is removed
```

## Acceptance Criteria
- [ ] `find .claude/roadmaps/ -mindepth 2 -maxdepth 2 -type d` returns no output (no subdirectories inside any roadmap directory, excluding the `archived/` directory which is a peer) (S1).
- [ ] `ls .claude/roadmaps/roadmap-1771113081/` lists exactly the roadmap `.md` files and no directories (S1).

## Data
**Inputs:** Roadmap file content; roadmap directory path
**Outputs:** `.md` file placed directly in `<project-root>/.claude/roadmaps/roadmap-{ts}/`
**State changes:** File system gains one flat file; no subdirectory entries created

## Traceability
- Parent FR: [FR-6.2](../frds/FRD-006-roadmap-file-conventions.md)
- ADR: [ADR-009](../../decisions/ADR-009-roadmap-naming.md)
