# Pipeline Experiments

One experiment per DAG phase run. Each tests a single variable to improve speed, quality, or coordination.

---

## EXP-001: Haiku Scaffold + Sonnet Refine (Model Pairing)
**Phase:** 3 (Topology & Entropy) | **Date:** 2026-02-22
**Hypothesis:** Splitting a task into haiku-scaffolds-fast then sonnet-refines-to-spec will be faster than a single sonnet worker writing from scratch, with equal or better quality.
**Method:** Task 3 (Canvas Topology Renderer) used two-stage approach: worker-3a (haiku) created all 4 files with boilerplate and basic implementation. worker-3b (sonnet) then refined to match FRD/ADR spec exactly. All other tasks used single sonnet workers as control.
**Result:** Pipeline completed successfully. Haiku scaffold: fast, 4 files created, 3 tests, zero warnings. Sonnet refine: slower than expected (~7 min vs ~4 min for single-sonnet workers on comparable tasks). Total wall-clock for task 3 was longer than single-sonnet control tasks. Quality: 3 tests passing, zero warnings -- adequate but not more thorough than single-sonnet output. Sonnet spent turns reading files/specs instead of refining.
**Verdict:** INCONCLUSIVE -- the pattern works mechanically but the stage-2 prompt was too generic. Sonnet wasted time orienting rather than refining. The variable being tested (model pairing) was confounded by prompt quality.
**Observation:** Haiku stage was fast (scaffolding done quickly, 3 tests passing, zero warnings). Sonnet refinement stage is slower than expected -- the generic "refine to spec" prompt forced sonnet to spend turns reading files and specs rather than refining. Lead prompt for stage 2 should pre-digest critical details (colors, algorithm constants, message formats) instead of saying "read the spec."
**Next:** Re-test in Phase 4 as EXP-002 with pre-digested stage-2 prompt. Include key constants, colors, message formats, and specific refinement targets inline. Measure sonnet refiner turn count vs single-sonnet turn count.

---

## Backlog

Ideas to test in future phases:

- **Pre-digested stage-2 prompts**: Include critical spec details (constants, colors, formats) directly in the sonnet refiner prompt instead of "read the spec"
- **Worker turn count tracking**: Measure how many turns each worker takes to complete, compare across models
- **Parallel code review agent**: Spawn a read-only reviewer alongside workers to catch issues before DONE
- **Task-level DAG granularity**: Split sections into individual tasks instead of one-task-per-section
