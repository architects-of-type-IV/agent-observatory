---
id: FRD-006
title: Roadmap File Conventions Functional Requirements
date: 2026-02-21
status: draft
source_adr: [ADR-009, ADR-011]
related_rule: []
---

# FRD-006: Roadmap File Conventions

## Purpose

This document specifies the functional requirements for creating, naming, storing, and archiving roadmap files used by multi-agent teams in the Observatory project. Roadmaps implement the Monad Method's 5-level work breakdown hierarchy (Phase, Section, Story, Task, Subtask) as flat Markdown files in a single directory. The flat-file-with-dotted-numbering convention allows any agent to read the full roadmap with a single `ls` without directory traversal.

ADR-009 governs this design. The user explicitly established a hard constraint against subdirectory structures after a prior session created nested directories in violation of the convention.

## Functional Requirements

### FR-6.1: Roadmap Directory Location

Roadmap directories MUST be created at `<project-root>/.claude/roadmaps/roadmap-{unix-timestamp}/` where `{unix-timestamp}` is the Unix epoch integer at the time of roadmap creation (e.g., `1771113081`). The parent directory `<project-root>/.claude/roadmaps/` MUST be created if it does not already exist. Each roadmap sprint or work session that warrants a new roadmap gets a new timestamp-keyed directory.

**Positive path**: A new team is spun up for a feature. The lead creates `.claude/roadmaps/roadmap-1771200000/` at the project root. All roadmap files for this sprint are placed inside that single directory.

**Negative path**: A roadmap directory named `.claude/roadmaps/roadmap-feature-auth/` (using a slug instead of a timestamp) MUST NOT be created. The naming must use a Unix timestamp integer. Slug-based names make chronological ordering and cross-reference harder.

---

### FR-6.2: Flat File Structure (No Subdirectories)

ALL roadmap files MUST be placed flat in a single roadmap directory. Subdirectories inside a roadmap directory MUST NOT be created under any circumstances. This is a hard constraint with no exceptions.

**Positive path**: A roadmap with 29 files covering a complete feature implementation places all 29 files directly in `.claude/roadmaps/roadmap-1771113081/`. Running `ls .claude/roadmaps/roadmap-1771113081/` returns all 29 files with no subdirectories.

**Negative path**: A developer creates `.claude/roadmaps/roadmap-1771113081/phase-1/1.1-auth.md`. This violates the flat-file convention. No subdirectories are ever permitted inside a roadmap directory. The user expressed explicit frustration with this pattern in a prior session: it MUST NOT happen.

---

### FR-6.3: Dotted Numbering File Naming Convention

Every roadmap file MUST be named with the pattern `N.N.N-slug.md` where the dotted prefix encodes the hierarchy level and position, and the slug is a short lowercase hyphen-separated description. Specifically:

- **Phase**: `N-slug.md` (e.g., `1-setup.md`)
- **Section**: `N.N-slug.md` (e.g., `1.1-database.md`)
- **Story**: `N.N.N-slug.md` (e.g., `1.1.1-schema.md`)
- **Task**: `N.N.N.N-slug.md` (e.g., `1.1.1.1-create-table.md`)
- **Subtask**: `N.N.N.N.N-slug.md` (e.g., `1.1.1.1.1-add-index.md`)

The dotted prefix MUST appear before the first hyphen. The slug MUST be lowercase and MUST use hyphens as word separators. The file extension MUST be `.md`.

**Positive path**: A task file is named `2.1.1.1-detect-role.md`. An agent can determine from the filename alone that this is a Task (4-level depth) in Phase 2, Section 1, Story 1. Filtering by prefix `ls 2.*.md` lists all Phase 2 items.

**Negative path**: A file named `detect-role.md` (no dotted prefix) or `2_1_1_1-detect-role.md` (underscores instead of dots) MUST NOT be created. Without the dotted prefix, hierarchy is lost and prefix-based filtering is impossible.

---

### FR-6.4: Five-Level Hierarchy

Roadmap hierarchies MUST use exactly these five levels with these exact names: **Phase** (depth 1), **Section** (depth 2), **Story** (depth 3), **Task** (depth 4), **Subtask** (depth 5). Numbering depth reflects hierarchy level: a depth-4 prefix (e.g., `2.1.3.2`) always indicates a Task. Files MUST NOT exceed depth 5. Files MUST NOT skip hierarchy levels (e.g., a Phase may not contain Tasks directly without intervening Sections and Stories).

**Positive path**: Phase 1 contains Sections 1.1 and 1.2. Section 1.1 contains Stories 1.1.1 and 1.1.2. Story 1.1.1 contains Tasks 1.1.1.1 and 1.1.1.2. Each level is present and correctly numbered.

**Negative path**: A file named `1.1.md` contains tasks directly with no Story-level intermediary. This skips hierarchy level 3 (Story). All five levels MUST be present in the breakdown when the work is complex enough to require task decomposition.

---

### FR-6.5: Roadmap Lifecycle During Team Work

A roadmap directory is active during the team's working session. Active roadmaps MUST remain at `<project-root>/.claude/roadmaps/roadmap-{ts}/` and MUST NOT be moved, renamed, or modified structurally while agents are reading them. Agents MUST be able to list and read roadmap files at any time during the team session.

**Positive path**: An agent reads `ls .claude/roadmaps/roadmap-1771113081/` to see all available tasks and filters by prefix `1.1.` to find all items in Section 1.1. The files are stable on disk throughout the session.

**Negative path**: The lead agent moves roadmap files to a different directory mid-session to "reorganize" them. Worker agents that have cached the directory path now encounter missing files. Roadmap files MUST NOT be relocated during an active team session.

---

### FR-6.6: Roadmap Archival on TeamDelete

When a team is deleted (via `TeamDelete` or the equivalent `gc.sh` cleanup script), its active roadmap MUST be moved (not copied) to `<project-root>/.claude/roadmaps/archived/`. The archived roadmap MUST retain its original directory name (`roadmap-{ts}/`) so it can be identified by timestamp after archival. The archival MUST preserve all file contents and the flat structure.

**Positive path**: `TeamDelete` is called for team `my-team`. The roadmap at `.claude/roadmaps/roadmap-1771113081/` is moved to `.claude/roadmaps/archived/roadmap-1771113081/`. All 29 files are present and readable after the move.

**Negative path**: The roadmap is deleted (not moved) on TeamDelete. Historical record of what was planned and built is lost. Archival to `archived/` MUST be performed instead of deletion.

---

### FR-6.7: Agent Discovery Protocol

Agents MUST discover available roadmap files using a two-step protocol: (1) list the roadmap directory with `ls .claude/roadmaps/roadmap-{ts}/` to see all files, then (2) filter by dotted prefix to find items at a specific hierarchy level (e.g., `ls .claude/roadmaps/roadmap-{ts}/ | grep '^2\.'` to find all Phase 2 items). Agents MUST NOT assume a directory structure exists inside the roadmap directory. Agents MUST NOT traverse subdirectories.

**Positive path**: An agent identifies the current roadmap timestamp from the lead's initial prompt, runs `ls .claude/roadmaps/roadmap-1771113081/`, parses the filenames to extract its assigned task ID (e.g., `2.1.1.1`), reads the corresponding file `2.1.1.1-detect-role.md`, and begins implementation.

**Negative path**: An agent calls `ls .claude/roadmaps/roadmap-1771113081/phase-2/` expecting a subdirectory. The path does not exist and the command fails. The flat structure is the contract; agents MUST NOT assume subdirectories.

---

### FR-6.8: Roadmap ID Format (Unix Timestamp)

Roadmap IDs MUST be Unix epoch timestamps expressed as decimal integers with no padding. The timestamp MUST be taken at the time the roadmap directory is created (not at the time the first file is written). The timestamp format `roadmap-{N}` where `{N}` is the result of `date +%s` (or equivalent `System.os_time(:second)` in Elixir) is the canonical form. Auto-incrementing integer sequences MUST NOT be used as roadmap IDs.

**Positive path**: At the moment of roadmap creation, `date +%s` returns `1771200000`. The directory is named `.claude/roadmaps/roadmap-1771200000/`. Multiple roadmaps created in a single day each get a unique timestamp, so they do not collide.

**Negative path**: A roadmap directory is named `.claude/roadmaps/roadmap-001/` using an auto-incrementing integer. This requires a coordination mechanism to determine the next available ID. Unix timestamps avoid this coordination overhead entirely.

---

### FR-6.9: Global Roadmap Protocol Registration

The flat-file-with-dotted-numbering convention MUST be documented as a global protocol accessible to all agent sessions. Specifically, the convention is registered in `~/.claude/CLAUDE.md` under the "Team Roadmap Protocol" heading. Any agent spawned in any project with access to the global CLAUDE.md can read the convention without project-specific onboarding.

**Positive path**: A freshly spawned worker agent reads `~/.claude/CLAUDE.md` as part of its context. It finds the Team Roadmap Protocol section and knows to look for roadmap files in `<project-root>/.claude/roadmaps/roadmap-{ts}/` with dotted-numbered filenames.

**Negative path**: The convention is documented only in a project-specific README that agents do not read by default. Agents in new sessions are unaware of the convention and create subdirectories or use non-standard naming. Global registration in `~/.claude/CLAUDE.md` prevents this.

---

## Out of Scope (Phase 1)

- Automated roadmap generation from a feature description (the roadmap is written by the lead or Monad Method process, not auto-generated from task data).
- Roadmap file format validation (content schema, required sections, etc.).
- Roadmap search or indexing across multiple `roadmap-{ts}/` directories.
- Roadmap diff or merge tooling for concurrent edits by multiple leads.
- UI display of roadmap hierarchy in the Observatory dashboard.

## Related ADRs

- [ADR-009](../../decisions/ADR-009-roadmap-naming.md) -- Flat File Roadmaps with Dotted Numbering; defines the directory structure, naming convention, lifecycle, and global protocol registration.
- [ADR-011](../../decisions/ADR-011-handler-delegation.md) -- Handler Delegation Pattern; shares the same sprint origin as ADR-009 (Team Inspector feature).
