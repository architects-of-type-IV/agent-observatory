# Monad Method Lesson Log

Lessons discovered during real pipeline execution. Each entry traces to a specific finding, identifies which Mode or gate leaked, and proposes a deterministic fix. These lessons are candidates for upstream skill amendments so all projects benefit.

---

## ML-001: FRD Internal Return Type Inconsistency

**Discovered:** 2026-02-22, Phase 3 Gate Validation
**Source finding:** FRD-009 FR-9.1 and FR-9.3 said `{:ok, score}` (2-tuple); FR-9.4/9.5/9.6 said `{:ok, score, severity}` (3-tuple)
**Leaked at:** Mode B Gate 2

### Root Cause

Mode B Gate 2 checks FR-to-UC coverage and structural integrity but does not cross-check return type signatures across FRs within the same FRD. When multiple FRs describe the same function's behavior at different stages (FR-9.1 defines the function, FR-9.4 defines a specific return path), the return type can drift between sections without detection.

### Proposed Fix

Add a Gate 2 check: for each FRD, extract all return type signatures mentioned in positive/negative path examples. Group by function name. Flag any function whose return type differs across FRs within the same FRD.

### Classification

Deterministic -- can be implemented as a pattern match on FRD positive/negative path code blocks.

---

## ML-002: ADR Scope Item Omitted from Phase Spec

**Discovered:** 2026-02-22, Phase 3 Gate Validation
**Source finding:** ADR-016 Decision section lists "basic zoom/pan" as Phase 1 scope. Phase 3 spec had no zoom/pan task.
**Leaked at:** Mode C generation

### Root Cause

The Mode C writer extracted capabilities that had dedicated FRs (FR-8.9 through FR-8.13) but missed capabilities listed in the ADR Decision section that were not broken into individual FRs. "Basic zoom/pan" appeared in ADR-016's Decision paragraph but FRD-008 did not create a dedicated FR for it.

### Proposed Fix

Mode C generation must perform a scope extraction pass on each governing ADR's Decision section before writing tasks. Every capability noun phrase in the Decision section must map to at least one task in the Phase spec. If a capability has no corresponding FR, Mode C must either create a task referencing the ADR directly or flag the gap for human review.

Secondary fix: Mode B FRD writers should ensure every capability in the governing ADR's Decision section has a corresponding FR. A "scope coverage" check at Gate 1.

### Classification

Requires two-stage fix: Mode B (FR completeness) + Mode C (ADR scope extraction). Both are deterministic.

---

## ML-003: Ambiguous ADR Term Left Vague in Phase Spec

**Discovered:** 2026-02-22, Phase 3 Gate Validation
**Source finding:** ADR-016 says "force-directed layout." Phase 3 spec render() subtask mentioned it but specified no algorithm parameters (force constants, displacement caps, ideal edge length).
**Leaked at:** Mode C generation

### Root Cause

Mode C writers reproduce ADR terminology verbatim when the ADR does not specify implementation parameters. "Force-directed layout" is a category of algorithms, not a specific algorithm. Without concrete parameters, parallel workers may produce divergent implementations.

### Proposed Fix

Mode C generation must expand ambiguous algorithm references into concrete parameters. When the ADR names a technique without specifying constants, the Mode C writer must select reasonable defaults and document them in the subtask. The selection should be noted as "Mode C default per ADR-NNN" so reviewers can trace the choice.

Gate check: every subtask that references an algorithm or technique must include at least one numeric parameter or concrete data structure choice. Subtasks containing only category names ("force-directed", "LRU cache", "bloom filter") without parameters fail the gate.

### Classification

Deterministic -- can be checked by scanning subtask text for algorithm keywords and requiring co-occurrence with numeric literals.

---

## ML-004: Short Module Names in Subtask Prose Evade Dependency Detection

**Discovered:** 2026-02-22, Phase 3 Gate Validation (dry-run)
**Source finding:** Subtask 3.3.4.3 said "Update `CausalDAG`'s `broadcast_delta/4`" -- modifying Section 3.1's module. But the DAG placed Sections 3.1 and 3.3 in parallel Wave 1.
**Leaked at:** Phase-to-DAG dependency detection (partially -- script scans subtask text but missed short names)

### Root Cause

Phase-to-DAG already scans full section content including subtask text (Step 3b, lines 222-227 for file paths; Step 3, lines 152-193 for module references). It detected neither because:
1. **File path detection** uses backtick-wrapped paths like `` `lib/observatory/mesh/causal_dag.ex` ``. The subtask didn't include the full file path.
2. **Module reference detection** matches full qualified names like `Observatory.Mesh.CausalDAG`. The subtask used the short name `CausalDAG`.

The script's detection works correctly when Mode C writers use full qualified module names or backtick-wrapped file paths. The leak is in the Mode C spec, not the script.

### Proposed Fix

**Primary (Mode C generation rule):** Mode C writers MUST use full qualified module names (`Observatory.Mesh.CausalDAG`) in subtask descriptions, never short names (`CausalDAG`). This enables the existing Phase-to-DAG detection to work. Add this as a Mode C gate check: scan subtask text for unqualified capitalized identifiers that match a known module's final segment but don't match the full qualified name.

**Secondary (script enhancement, optional):** Build a short-name-to-full-name map from `mod-defs.tsv` (e.g., `CausalDAG` -> `Observatory.Mesh.CausalDAG`). Do a second reference scan using short names. Risk: higher false positive rate on common names.

### Classification

Primary fix is deterministic (Mode C generation rule + gate check). Secondary fix has false positive risk and may not be worth the complexity.

---

## ML-005: Cross-Phase File Overlap Not Enforced at Task Level

**Discovered:** 2026-02-22, Phase 3 Gate Validation
**Source finding:** Tasks 3.6.1 and 3.6.2 modify `schema_interceptor.ex` (a Phase 2 file). The Phase 3 frontmatter declares `depends_on: [phase: 2]` but this constraint is invisible at the task level in tasks.jsonl. A DAG lead spawning Phase 3 workers would not see the cross-phase file dependency.
**Leaked at:** Phase-to-DAG scope (by design -- it operates per-phase)

### Root Cause

Phase-to-DAG generates tasks.jsonl for one phase at a time. It has no knowledge of files touched by other phases. The `depends_on` field in the Phase frontmatter is metadata for human coordination, not machine-enforced. When tasks.jsonl is generated for Phase 3, tasks that touch Phase 2 files have no `blocked_by` reference to Phase 2 completion.

### Proposed Fix

Two options:

**Option A (recommended):** Phase-to-DAG accepts an optional `--prior-phase` flag pointing to the prior phase's tasks.jsonl. It reads the prior phase's file ownership map and checks each new task's file list against it. Any overlap generates a `blocked_by` edge to the prior phase's final task (the migration/integration task that gates phase completion).

**Option B:** Mode C Gate adds a cross-phase file overlap check. For each Phase N spec, extract all file paths. Compare against file paths in Phases 1 through N-1. Flag any overlap and require the Phase spec to explicitly document the dependency in the affected task (not just the frontmatter).

### Classification

Option A is deterministic and machine-enforceable. Option B requires human judgment to resolve flags.

---

## Summary

| ID | Mode Leaked | Severity | Fix Type |
|----|------------|----------|----------|
| ML-001 | Mode B Gate 2 | Low | Gate check addition |
| ML-002 | Mode B + Mode C | Medium | Two-stage: FR completeness + scope extraction |
| ML-003 | Mode C | Medium | Subtask parameter gate check |
| ML-004 | Phase-to-DAG | High | Script enhancement (subtask text scanning) |
| ML-005 | Phase-to-DAG | High | Script enhancement (cross-phase file check) |

### Evaluation Status

All 5 lessons pending evaluation for upstream skill amendments. When approved, each lesson should produce a concrete diff to the relevant skill file (`mode-b/SKILL.md`, `mode-c/SKILL.md`, or `phase-to-dag/phase-to-dag.sh`).
