# The Monad Method

> Xander's personal methodology for turning ideas into fully specified Genesis Nodes. This is the flow The Monad will guide users through.

## Overview

The method has **3 modes** that progress linearly but allow looping within each mode. Two checkpoint gates separate the modes. No code is written until the entire specification is clear.

```
Brief -> Draft ADRs -> Research Loop -> FRDs -> FRs -> Use Cases -> Roadmap
         \___________Mode A__________/  \____________Mode B____________/  Mode C
```

## Mode A -- Discover

**Goal:** Converge on architectural decisions. Record trade-offs explicitly.

### Flow

1. Write a **brief** -- short, opinionated description of the idea
2. **Brain dump draft ADRs** -- one per strong intuition (e.g., "bi-temporal graph", "event sourcing")
3. **Research loop** (per ADR):
   - Start a dedicated conversation (new file per topic)
   - Research against pattern library (50+ OSS frameworks/libraries)
   - Compare approaches, discuss best practices, understand WHY others chose what they chose
   - Iterate until the picture is clear
4. **Finalize each ADR**:
   - What was chosen and why
   - What was deliberately rejected and why (equally important)
   - Extract features (functional requirements) and link them to the ADR
   - Promote ADR: `draft` -> `proposed`
5. **Checkpoint** -- Snapshot: ADR statuses, open questions, next decisions

Repeat steps 3-5 until confident in a first implementation phase.

### Artifacts

| Artifact | Purpose | Genesis Node Field |
|----------|---------|-------------------|
| Project brief | The idea, non-negotiables | `brief` |
| Conversations | The "thinking trail" | `research` |
| ADR files | Decisions + rejected alternatives | `adrs` |
| Checkpoint | State snapshot | (metadata) |

### Key Principle

The conversations ARE the research. Each ADR gets its own deep-dive. The "why not" is as valuable as the "why" -- it prevents relitigating decisions later.

---

## Mode B -- Define

**Goal:** Translate decisions into testable behavior. Requirements are normative (what MUST be true), not implementation plans.

### Flow

1. For each ADR, create **1..N FRDs** that fall out of the decision
2. **GATE: FRD coverage** -- a validator agent checks that every ADR decision is covered by at least one FRD. No orphan decisions.
3. For each FRD, write **individual FRs** (FR-N.1, FR-N.2, ...) using positive/negative path format
4. **GATE: FR consistency** -- a validator agent checks that every FR has both positive and negative paths, and that FRD `depends_on` declarations are consistent.
5. For each FR, create **1..N use cases** with Gherkin scenarios, acceptance criteria, and rules
6. **GATE: UC completeness** -- a validator agent checks that every FR has at least one UC, every Gherkin scenario maps to an AC, and no orphan FRs exist.
7. **Checkpoint** -- Requirements freeze for this phase

Gates are validation steps executed by a dedicated agent between production steps. They catch errors at the cheapest point to fix them -- before the next step compounds them.

### Artifacts

| Artifact | Purpose | Genesis Node Field |
|----------|---------|-------------------|
| FRD files | Grouped functional requirements per ADR | `features` |
| UC files | Use cases per FR | `features[].useCases` |
| Inline rules | Rules scoped to one UC | embedded in UC |
| Shared RULE files | Rules reused across UCs | `businessRules` / `functionalRules` |
| NFR files | Cross-cutting non-functionals | `nonFunctionalRules` |

### The Reuse Rule

- If a rule is **used by one UC only** -> keep it inline in that UC
- If a rule is **shared across multiple UCs** -> extract to a standalone RULE file and reference it

This prevents both duplication and a premature "rule zoo."

### Artifact Ownership

Each piece of truth lives in exactly one place:
- **ADRs** own decisions (the "what" and "why")
- **FRDs** own grouped behavior descriptions (the "what it does"); individual FRs define each requirement
- **UCs** own testable scenarios with Gherkin (the "how to verify")
- **Rules** own constraints (the "boundaries")

Everything else references these. No rewriting the same truth in multiple places.

---

## Mode C -- Build

**Goal:** Turn stable requirements into an implementation plan that AI agent swarms can execute.

Mode C only starts when the Genesis Node is totally clear -- all ADRs proposed, all FRs have UCs with acceptance criteria, all rules documented. The roadmap is the LAST artifact, not an early guess.

### The 4-Level Hierarchy

```
Phase.Section.Task.Subtask
1    .1      .1   .1
```

| Level | What it is | File naming | Example |
|-------|-----------|-------------|---------|
| **Phase** | Goals + linked ADRs | `1-storage-foundation.md` | `1` Foundation |
| **Section** | Goal + list of tasks | `1.1-project-scaffolding.md` | `1.1` Project scaffolding |
| **Task** | Implementation chunk, links to UC(s) | `1.1.1-mix-project-setup.md` | `1.1.1` Create project skeleton |
| **Subtask** | Handoff atom for swarm agents | `1.1.1.1-create-mix-project.md` | `1.1.1.1` `mix new our_project --sup` |

### The Phase File Is the Source of Truth

The Phase file is a **monolith** -- it contains every Section, Task, and Subtask inline with checkbox status. Individual files at each level exist as **focused handoff atoms** for agents that need context on their specific scope. The Phase file is the roadmap; individual files are the work orders.

```
1-storage-foundation.md          <- Source of truth (all tasks + checkboxes)
  ├── 1.1-project-scaffolding.md <- Section scope + task list
  │   ├── 1.1.1-mix-setup.md    <- Task context + UC links
  │   │   ├── 1.1.1.1-create.md <- Subtask handoff atom
  │   │   └── 1.1.1.2-deps.md
  │   └── 1.1.2-nif-config.md
  └── 1.2-nif-wrapper.md
```

When a swarm agent completes a subtask, the Phase file checkbox is updated. Individual files are generated from the Phase file during roadmap creation -- they are NOT maintained separately.

### JSONL Index

A machine-readable `index.jsonl` tracks every item for swarm coordination:

```jsonl
{"type":"phase","id":"1","title":"Storage Foundation","status":"in_progress","governed_by":["ADR-000","ADR-002"],"file":"1-storage-foundation.md"}
{"type":"section","id":"1.1","phase_id":"1","title":"Project Scaffolding","status":"complete","file":"1.1-project-scaffolding.md"}
{"type":"task","id":"1.1.1","section_id":"1.1","title":"Mix Project Setup","status":"complete","governed_by":["ADR-000"],"parent_uc":["UC-0001"],"file":"1.1.1-mix-project-setup.md"}
{"type":"subtask","id":"1.1.1.1","task_id":"1.1.1","title":"Create mix project","status":"complete","owner":"worker-a","file":"1.1.1.1-create-mix-project.md"}
```

The index is the machine interface; the Phase file is the human interface. Both are kept in sync -- the index is generated from the Phase file, never manually edited.

Swarm coordinators query the index directly:
```bash
jq -c 'select(.status == "pending" and .type == "subtask")' index.jsonl
```

### Flow

1. Build the **FRD dependency graph** from `depends_on` declarations (Mode B output)
2. Define **Phases** with goals, linked ADRs, and the `governed_by` field connecting each phase to its governing decisions
3. Break each Phase into **Sections** with clear scope
4. Break each Section into **Tasks** (implementation chunks linked to UCs via `parent_uc`)
5. Break each Task into **Subtasks** using the handoff format (see below)
6. Generate **individual files** and the **JSONL index** from the Phase file
7. **Checkpoint** -- Roadmap stabilization

### Subtask Handoff Format

Each subtask file is a self-contained work order for a swarm agent:

```yaml
---
id: 1.1.1.1
title: Create mix project
status: pending
task_id: 1.1.1
governed_by: [ADR-000]
parent_uc: [UC-0001]
---

goal: Working mix project with supervision tree
allowed_files:
  - lib/memories/application.ex
  - mix.exs
  - config/config.exs
blocked_by: []
steps:
  - Run mix new memories --sup
  - Add dependencies to mix.exs
  - Configure application supervision tree
done_when: "mix compile --warnings-as-errors"
```

Fields:
- `goal` -- what success looks like (one sentence)
- `allowed_files` -- file scope boundary; the agent MUST NOT edit files outside this list
- `blocked_by` -- subtask IDs that must complete first (derived from FRD `depends_on`)
- `steps` -- ordered list of actions
- `done_when` -- machine-executable verification command
- `governed_by` -- ADR(s) the agent should read for architectural context
- `parent_uc` -- UC(s) whose Gherkin scenarios define the expected behavior

### Artifacts

| Artifact | Purpose |
|----------|---------|
| Phase file | Source of truth: goals, linked ADRs, all tasks inline with checkboxes |
| Section file | Focused scope for a section's tasks (generated from Phase file) |
| Task file | Links to UC(s)/FR(s), implementation context (generated from Phase file) |
| Subtask file | Handoff atom with goal, allowed files, steps, done-when (generated from Phase file) |
| `index.jsonl` | Machine-readable status index for swarm coordination |
| Task summary | Post-implementation recap (subtask summaries = commit messages) |
| Section/Phase review | "What we'd do differently" retrospective |

### Key Principles

- **Phase file is the single source of truth.** Individual files and the JSONL index are generated from it.
- **Task summaries are the sweet spot for summaries.** Subtask-level summaries are just commit messages. Section and Phase reviews capture lessons learned.
- **`governed_by` links every roadmap item back to its ADR.** When a swarm agent picks up subtask 1.2.1.1, it knows which ADR to read for context.
- **`parent_uc` links every task to its verification scenarios.** The agent reads the UC's Gherkin to understand what tests to write.

---

## The Linking Chain

The full traceability path from decision to code:

```
ADR -> FRD (containing FRs) -> UC -> Task -> Subtask
```

### What links where

| Artifact | Contains links to | Machine-readable field |
|----------|------------------|----------------------|
| **ADR** | FRDs it enables, rejected alternatives | -- |
| **FRD** | Parent ADR(s), dependent FRDs, file scope, list of FRs | `source_adr`, `depends_on`, `file_scope` |
| **FR** | Parent FRD, list of UCs verifying it | (inline in FRD) |
| **UC** | Parent FR, Gherkin scenarios, rules, ACs | `parent_fr`, `adrs` |
| **Task** | Parent Section, UCs it implements, governing ADRs | `parent_uc`, `governed_by` |
| **Subtask** | Parent Task, blocked-by deps, allowed files, done-when | `blocked_by`, `allowed_files`, `done_when` |

### Bidirectional validation

A validator agent can check linkage integrity by querying frontmatter:
- **Orphan FRs**: FRs with no UC covering them (`parent_fr` not referenced by any UC)
- **Orphan UCs**: UCs whose `parent_fr` doesn't exist in any FRD
- **Coverage gaps**: ADR decisions with no FRD (`source_adr` not referenced)
- **Scope conflicts**: Subtasks with overlapping `allowed_files` that are scheduled in parallel

This is enough for navigation without turning it into bureaucracy.

---

## Checkpoints

Three checkpoint moments in the method:

1. **After ADRs become proposed** -- Decision stabilization (end of Mode A)
2. **After FRD/FR/UC set feels complete** -- Requirements stabilization (end of Mode B)
3. **After Phase/Section/Task breakdown is done** -- Roadmap stabilization (end of Mode C)
4. During conversations, whenever there's a pause or the user wants to take a break

Each checkpoint answers:
- What is settled
- What is open
- What is next

---

## How The Monad Uses This

The Monad guides users through Modes A and B conversationally:

1. **Mode A conversations** -- The Monad asks probing questions about the idea, helps research patterns, renders comparison cards and trade-off matrices via json-render, and synthesizes answers into ADR drafts
2. **Mode B conversations** -- The Monad walks through each ADR's FRDs, decomposes into FRs, creates Use Cases with Gherkin scenarios, and flags missing edge cases
3. **Checkpoints** -- The Monad presents a checkpoint summary (progress bars, status badges, open questions) and asks for confirmation before advancing

The Monad's json-render compositions are not decoration -- they're thinking tools. A comparison grid during Mode A helps the user SEE the trade-offs. A progress dashboard at checkpoint time shows what's complete and what's missing.

---

## Templates

Artifact templates for each mode. Mode A and B templates define what to specify; Mode C templates define what to build.

### Project Brief (`project.md`)
- Idea (1-3 sentences)
- Non-negotiables (what MUST be true)
- Constraints (tech, time, taste)

### ADR (`ADR-NNN-*.md`)

Frontmatter:
- `id`, `title`, `date`, `status` (pending|proposed|accepted|rejected|superseded)
- `related_tasks`, `parent` (ADR lineage), `superseded_by`

Body:
- Related Requirements (cross-references)
- Related ADRs (cross-references)
- Context (what problem, why a decision is needed)
- Decision (with subsections as needed -- details, tables, code examples)
- Rationale (why this over alternatives, key benefits)
- Alternatives Rejected (table: Alternative | Reason)
- References (table: Reference | Location | Notes)
- Changelog (status transitions with dates)

### Checkpoint

Structure varies by context. Organized by **dependency layers**, not flat lists.

Per layer:
- Table of ADRs with status and context-sensitive columns (Notes, Open Questions, Dependencies, Blocks)

For in-progress ADRs:
- Resolved Questions table (Question | Resolution)
- Open Questions table (Question | Status)
- Key Decisions with rationale

Global sections:
- Deferred items (table: ADR | Title | Reason)
- Recommended Next Steps (ordered, actionable)

### Conversation

Living research journal. UPDATEs appended chronologically, never edited in place.

Header:
- Title, Date, Topic, Status (In Progress | Complete)

Body:
- Context (which ADR(s) this informs)
- Research sections (framework comparisons, benchmark tables, architecture analysis)
- Decision Framework (options with sourcing, recommendations)
- Questions Answered (resolved during session)
- New Questions (emerged during session)
- Research Tasks (proactive follow-up items)
- Documents Added to References

Updates:
- `## UPDATE: <topic> (YYYY-MM-DD)` sections appended as research continues
- Questions move from "New" to "Resolved" with strikethrough

Session Status (when complete):
- Findings Summary
- Next Actions

### Research

Archival pattern analysis. Gets archived once ADRs are written.

Header:
- Title, Status (Active | Archived), Superseded by (ADR references), key file locations

Body:
- Executive Summary (what and why, 2-3 sentences)
- Implementation References (table: Component | Our Implementation | Status)
- Deep Analysis (source code walkthroughs, step-by-step pipelines, exact file paths + line numbers)
- Mapping Tables ("Theirs vs Ours" for prompts, fields, methods, patterns)
- Conclusion (coverage matrix: Feature | ADR Coverage)

### Functional Requirements Document (`FRD-NNN-*.md`)

Frontmatter:
- `id`, `title`, `date`, `status`, `source_adr` (parent ADR list)
- `depends_on` (list of FRD IDs this FRD requires -- e.g., FRD-003 depends on FRD-002 because Fact FKs reference Entity)
- `file_scope` (list of file paths this FRD's implementation will touch -- enables parallel execution with disjoint scopes)

Body:
- Purpose (role in the system, which ADRs govern design)
- Functional Requirements (FR-N.1, FR-N.2, ... each with requirement statement + positive path + negative path)
- Out of Scope (deferred capabilities with phase/ADR references)
- Related ADRs (cross-references)

See template: `SPECS/_templates/frd.md`

### Use Case (`UC-NNNN-*.md`)

Frontmatter:
- `id`, `title`, `status`, `parent_fr`, `adrs`

Body:
- Intent (what this UC accomplishes)
- Primary Actor (single actor)
- Supporting Actors
- Preconditions
- Trigger
- Main Success Flow (numbered steps)
- Alternate Flows (A1, A2, ...)
- Failure Flows (F1, F2, ...)
- Gherkin Scenarios (S1, S2, ... -- one per flow, maps 1:1 to ACs)
- Acceptance Criteria (checkbox list, each referencing a scenario)
- Data (Inputs, Outputs, State Changes)
- Traceability: parent FR + ADR references

See template: `SPECS/_templates/uc.md`

---

## Artifact Pipeline

How templates relate to each other in the research-to-decision flow:

```
Research (analyze external patterns)
    -> Conversation (discuss + decide)
        -> ADR (record decision)
            -> FRD (group requirements, declare depends_on + file_scope)
                -> FR (define individual behavior)
                    -> [GATE: coverage + consistency]
                        -> UC (specify testable scenarios with Gherkin)
                            -> [GATE: completeness]
                                -> Phase file (monolith roadmap)
                                    -> index.jsonl (machine-readable)
                                        -> Subtask handoff atoms (swarm pickup)
```

Checkpoints sit at the boundaries between modes. Gates sit between steps within Mode B.

---

## Open Questions

- How branch conditions in the flow affect phase ordering (e.g., if user mentions technical constraints early, does Mode A's research loop prioritize those ADRs?)
- Conversation-to-artifact mapping: does The Monad auto-populate fields, or present drafts for user approval?
- ~~Feature vs FR naming: the other LLM suggests keeping "features" as FR files for clean mapping. Confirm?~~ **Resolved:** FRDs group FRs; individual FRs live inside FRDs.
- ~~Mode C templates (Phase, Section, Task, Subtask) -- to be designed later~~ **Resolved:** Phase file is monolith source of truth; individual files + JSONL index are generated. Subtask handoff format defined with goal/allowed_files/blocked_by/steps/done_when.
