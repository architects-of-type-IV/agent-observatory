---
id: UC-0158
title: Register roadmap convention in global CLAUDE.md for cross-session availability
status: draft
parent_fr: FR-6.9
adrs: [ADR-009]
---

# UC-0158: Register Roadmap Convention in Global CLAUDE.md for Cross-Session Availability

## Intent
The flat-file-with-dotted-numbering roadmap convention is documented in `~/.claude/CLAUDE.md` under the "Team Roadmap Protocol" heading. Any agent spawned in any project with access to the global CLAUDE.md can read the convention without project-specific onboarding. This ensures cross-session, cross-project availability of the protocol without repetition in individual project READMEs.

## Primary Actor
Developer (registering the protocol) / Agent (reading the protocol)

## Supporting Actors
- `~/.claude/CLAUDE.md` (global agent context file)
- All agent sessions that load `~/.claude/CLAUDE.md` as context

## Preconditions
- The roadmap convention has been established and is stable.
- `~/.claude/CLAUDE.md` exists and is readable by agent sessions.

## Trigger (registration)
The convention is identified as stable and worth global registration, prompting a developer to add it to `~/.claude/CLAUDE.md`.

## Trigger (reading)
An agent is spawned in a new session and reads `~/.claude/CLAUDE.md` as part of its context.

## Main Success Flow (registration)
1. Developer opens `~/.claude/CLAUDE.md`.
2. Under a "Team Roadmap Protocol" heading, the developer documents: directory location pattern, flat structure requirement, dotted-numbering format, five-level hierarchy names, and archival behaviour.
3. The section is concise and actionable (agents can follow it without human interpretation).
4. The file is saved.

## Main Success Flow (reading)
1. An agent is spawned in a new project session.
2. The agent reads `~/.claude/CLAUDE.md` as part of its startup context.
3. The agent finds "Team Roadmap Protocol" and knows: roadmaps live at `<project-root>/.claude/roadmaps/roadmap-{ts}/`, files are flat with dotted-numbered names, no subdirectories exist.
4. The agent correctly locates and reads roadmap files without project-specific onboarding.

## Alternate Flows

### A1: Agent in a project without a roadmap
Condition: No roadmap directory exists for the current project.
Steps:
1. The agent reads the global protocol and knows where to look.
2. The agent finds no `roadmap-{ts}/` directory.
3. The agent reports to the lead that no roadmap exists yet.
4. The lead creates one following the protocol.

## Failure Flows

### F1: Convention documented only in project-specific README
Condition: The convention is written in `<project-root>/README.md` but not in `~/.claude/CLAUDE.md`.
Steps:
1. A freshly spawned agent reads `~/.claude/CLAUDE.md` and finds no Team Roadmap Protocol section.
2. The agent does not know to look in `README.md`.
3. The agent creates subdirectories or uses non-standard naming in a new project.
Result: Convention violations occur in every new project where the protocol was not globally registered.

## Gherkin Scenarios

### S1: Global CLAUDE.md contains the Team Roadmap Protocol section
```gherkin
Scenario: ~/.claude/CLAUDE.md has a Team Roadmap Protocol heading
  Given the global ~/.claude/CLAUDE.md exists
  When grep -n "Team Roadmap Protocol" ~/.claude/CLAUDE.md is executed
  Then the command returns at least one match
  And the matched section describes the roadmap directory pattern and flat structure requirement
```

### S2: Agent reads the protocol and creates a correct roadmap
```gherkin
Scenario: An agent reads the global CLAUDE.md and creates a conforming roadmap directory
  Given the global CLAUDE.md contains the Team Roadmap Protocol
  When a freshly spawned agent is told to create a roadmap for a new sprint
  Then the agent creates .claude/roadmaps/roadmap-{ts}/ with a Unix timestamp
  And all files are placed flat with dotted-numbered names
  And no subdirectories are created
```

## Acceptance Criteria
- [ ] `grep -n "Team Roadmap Protocol" ~/.claude/CLAUDE.md` returns a match (S1).
- [ ] The section in `~/.claude/CLAUDE.md` mentions: timestamp-based directory naming, flat file structure (no subdirectories), dotted-number file naming (S1).
- [ ] An agent session that reads only `~/.claude/CLAUDE.md` can produce a conforming roadmap without additional project documentation (verified by manual or agent-executed test) (S2).

## Data
**Inputs:** Roadmap convention specification; `~/.claude/CLAUDE.md` file
**Outputs:** "Team Roadmap Protocol" section in `~/.claude/CLAUDE.md`; agents that follow the protocol without project-specific onboarding
**State changes:** `~/.claude/CLAUDE.md` gains or already has the protocol section; no runtime state changes

## Traceability
- Parent FR: [FR-6.9](../frds/FRD-006-roadmap-file-conventions.md)
- ADR: [ADR-009](../../decisions/ADR-009-roadmap-naming.md)
