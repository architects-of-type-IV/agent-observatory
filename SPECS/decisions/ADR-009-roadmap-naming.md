---
id: ADR-009
title: Flat File Roadmaps with Dotted Numbering
date: 2026-02-14
status: accepted
related_tasks: []
parent: null
superseded_by: null
---
# ADR-009 Flat File Roadmaps with Dotted Numbering
[2026-02-14] accepted

## Related ADRs
- [ADR-011](ADR-011-handler-delegation.md) Handler Delegation Pattern (both emerged during Team Inspector sprint)

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Team Inspector Design | [CONV-003](../conversations/CONV-003-team-inspector.md) | Roadmap naming established during Sprint 1-2 |
| Session JSONL | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/8585be9e-149a-4133-bed8-ef55dd380dc9.jsonl` | Raw session transcript |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-14T23:06:36Z | "Phase.Section.Story.Task.Subtask the 5 levels of artifacts" |
| 2026-02-14T23:11:32Z | Roadmap stored in `{project-folder}/.claude/roadmaps/roadmap-{NNN}/`, archived on TeamDelete |
| 2026-02-14T23:13:12Z | `roadmap-{unixtimestamp}` -- simpler than auto-incrementing IDs |
| 2026-02-15T00:04:45Z | User frustrated with subdirectories: "Is it that hard to understand the naming convention?" |

## Context

Multi-agent teams need structured work breakdown. Flat task lists (like `tasks.jsonl`) lack hierarchy for complex features. The user's Monad Method defines a 5-level hierarchy (Phase > Section > Story > Task > Subtask) for turning ideas into implementable work.

The question was how to store these artifacts on disk so agents can read them independently.

## Decision

- **Format:** `roadmap-{unix-timestamp}/` directory at `<project>/.claude/roadmaps/`
- **ALL files flat in ONE directory** -- NO subdirectories, ever
- **Dotted numbering:** `N.N.N-slug.md` (e.g., `2.1.1.1-detect-role.md`)
- **5 levels:** Phase(1).Section(1.1).Story(1.1.1).Task(1.1.1.1).Subtask(1.1.1.1.1)
- **Lifecycle:** Active during team work, moved to `.claude/roadmaps/archived/` on TeamDelete

## Rationale

Flat files with dotted numbering give agents a single `ls` to see all work items. No directory traversal needed. The dotted naming preserves hierarchy information without requiring directory nesting. Unix timestamps for roadmap IDs are simpler than auto-incrementing sequence numbers.

The user was explicitly frustrated when subdirectories were created in a prior session -- this is a hard constraint.

## Consequences

- Agents read roadmap files with `ls .claude/roadmaps/roadmap-{ts}/` + filter by prefix
- Roadmap archived on TeamDelete (preserves record of what was done)
- Added to `~/.claude/CLAUDE.md` as global Team Roadmap Protocol
- Example: `.claude/roadmaps/roadmap-1771113081/` with 29 flat files covering the Team Inspector feature
