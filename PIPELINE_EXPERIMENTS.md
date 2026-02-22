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

## EXP-002: Parallel Code Review Agent (Wave 4)
**Phase:** 4 (Gateway Infrastructure & HITL) | **Date:** 2026-02-22
**Hypothesis:** Spawning a read-only Explore agent alongside the two wave-4 parallel workers (tasks 4 & 5) that reviews their output files will catch cross-task integration issues before DONE, reducing lead verification failures and fix-then-retry cycles.
**Method:** When wave 4 starts (tasks 4 and 5 run simultaneously), spawn a lightweight Explore agent that reads the output files from both workers after they report DONE but before the lead runs done_when. The reviewer flags cross-task integration gaps: mismatched function signatures, missing aliases, PubSub topic name mismatches, undefined function calls. Control: waves 1-3 and 5-6 run without a reviewer.
**Measurement:** (1) Count of lead verification failures (done_when fails on first try) in wave 4 vs other waves. (2) Count of issues flagged by reviewer that would have caused done_when failure. (3) Wall-clock overhead of the review step.
**Result:** Reviewer completed in ~2 minutes. Found ZERO integration issues between tasks 4 (HITLRelay) and 5 (HITL HTTP Endpoints). Checked 7 categories: function signatures, aliases, PubSub topics, struct fields, router wiring, supervisor ordering, return type handling. All PASS. Both tasks' done_when passed on first try after review -- consistent with the 0-issue finding. Control waves (1-3, 5-6) also had 0 done_when failures on first try (task 7 had 1 sandbox mode fix, unrelated to integration).
**Verdict:** INCONCLUSIVE -- the reviewer worked mechanically and produced a thorough report, but found nothing. This could mean: (a) the lead's shared API contract in worker prompts prevented mismatches, or (b) the reviewer adds overhead without catching issues that wouldn't surface in done_when anyway. Need a wave with actual integration gaps to measure true value.
**Next:** Re-test in a future phase where parallel workers have more complex cross-module interactions (e.g., shared PubSub consumers, bidirectional calls). Also consider: does the ~2min overhead justify itself if done_when catches the same issues? Track done_when first-try failure rate across phases to establish baseline.

---

## Backlog

Ideas to test in future phases:

- **Pre-digested stage-2 prompts**: Include critical spec details (constants, colors, formats) directly in the sonnet refiner prompt instead of "read the spec"
- **Worker turn count tracking**: Measure how many turns each worker takes to complete, compare across models
- **Parallel code review agent**: Spawn a read-only reviewer alongside workers to catch issues before DONE
- **Task-level DAG granularity**: Split sections into individual tasks instead of one-task-per-section
- **Model selection per task**: Opus for greenfield architecture, Sonnet for well-specified contracts and verification tasks. Measure quality delta vs cost savings.
- **Reviewer on complex parallel waves only**: Skip reviewer when parallel workers share explicit API contracts in prompts; only review when contracts are implicit
