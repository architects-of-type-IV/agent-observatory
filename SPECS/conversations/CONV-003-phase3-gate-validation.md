# Phase 3 Pre-DAG Gate Validation Conversation

**Date**: 2026-02-22
**Topic**: Validating Phase 3 (Topology & Entropy) spec against governing ADRs and FRDs before tasks.jsonl generation
**Status**: Complete

## Referenced ADRs

| ADR | Title | Relevance |
|-----|-------|-----------|
| [ADR-016](../decisions/ADR-016-canvas-topology-renderer.md) | Canvas-Based Topology Map Renderer | Governs JS hook structure, node colors, PubSub topic, zoom/pan scope |
| [ADR-017](../decisions/ADR-017-causal-dag-parent-step-id.md) | Causal DAG via parent_step_id | Governs ETS data model, orphan buffer, cycle prevention, delta broadcast |
| [ADR-018](../decisions/ADR-018-entropy-score-loop-detection.md) | Entropy Score as Loop Detection | Governs sliding window, uniqueness ratio, thresholds, AlertEvent fields |
| [ADR-015](../decisions/ADR-015-gateway-schema-interceptor.md) | Gateway Schema Interceptor | Cross-phase: EntropyTracker call site in SchemaInterceptor |
| [ADR-021](../decisions/ADR-021-hitl-intervention-api.md) | HITL Manual Intervention API | Referenced by LOOP threshold Pause-and-Inspect action |

## Context

Phase 2 (Gateway Core) is being executed by an active DAG team. Phase 3 (Topology & Entropy) is the next phase. Before generating tasks.jsonl, we need to validate that the Phase 3 implementation spec faithfully implements the governing ADRs and that all FRs and UCs are traceable to implementation tasks.

Two validation passes were performed:
1. **Mode C Gate**: FR coverage, UC coverage, ADR coverage, hierarchy integrity, done_when completeness
2. **ADR Alignment**: Spec-to-ADR drift analysis checking every decision point in ADR-016, ADR-017, ADR-018

## Open Questions

None remaining -- all 5 findings resolved.

---

## Research

### Mode C Gate Results

All 7 gate checks passed:
- 24/24 FRs covered (13 from FRD-008, 11 from FRD-009)
- 24/24 UCs traced (UC-0230 through UC-0253)
- 5/5 ADRs referenced in governed_by fields
- Hierarchy integrity clean (6 sections, 23 tasks, 57 subtasks -> now 24 tasks, 60 subtasks after zoom/pan addition)
- All subtasks have done_when commands

### ADR Alignment Results

ADR-017 (CausalDAG): Clean alignment, no drift.
ADR-018 (Entropy): Clean alignment. FRD-009 had a return type inconsistency (FR-9.1/9.3 said 2-tuple, FR-9.4+ said 3-tuple).
ADR-016 (Canvas Renderer): Two findings -- zoom/pan omitted from Phase 1 scope, force-directed layout underspecified.

---

## Decisions

| Topic | Decision | Rationale | ADR |
|-------|----------|-----------|-----|
| TopologyBuilder subscription model | Direct per-session PubSub subscription via `subscribe_to_session/1` | Eliminates hidden cross-section dependency on `causal_dag.ex` modification; enables parallel Wave 1 execution of CausalDAG and Canvas tasks | ADR-016, ADR-017 |
| Cross-phase dependency enforcement | Explicit warning in Section 3.6 preamble + manual blocked_by in tasks.jsonl | Phase-to-DAG script detects intra-phase but not cross-phase file overlaps; Phase 2 must complete before 3.6 starts | ADR-015, ADR-018 |
| Zoom/pan inclusion | Added task 3.3.6 with 3 subtasks for wheel zoom, mouse pan, and inverse-transform hit detection | ADR-016 explicitly scopes "basic zoom/pan" to Phase 1; spec had omitted it | ADR-016 |
| Force-directed layout algorithm | Specified spring-electrical model in render() subtask (repulsive F=500/d^2, spring F=(d-80)*0.01, 10px cap) | Prevents divergent worker implementations; simple enough for a single render() function | ADR-016 |
| FRD-009 return type fix | Amended FR-9.1 and FR-9.3 positive paths to use 3-tuple `{:ok, score, severity}` | Consistent with FR-9.4/9.5/9.6 which already used the 3-tuple form | ADR-018 |

---

## Next Steps

- [x] Fix Warning 1: Rewrite 3.3.4.1/3.3.4.3 to use direct subscription model
- [x] Fix Warning 2: Add cross-phase dependency note to Section 3.6 preamble
- [x] Fix Warning 3: Add task 3.3.6 (zoom/pan) with 3 subtasks
- [x] Fix Info 4: Specify force-directed layout algorithm in 3.3.2.2
- [x] Fix Info 5: Amend FR-9.1 and FR-9.3 return types in FRD-009
- [x] Update index.jsonl with new/modified entries
- [ ] Generate tasks.jsonl via /phase-to-dag (after Phase 2 completes)
- [ ] Execute Phase 3 via /dag run
