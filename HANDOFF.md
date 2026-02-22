# Observatory - Handoff

## Current Status: Phase 3 Topology & Entropy COMPLETE (2026-02-22)

### Just Completed

**Phase 3: Topology & Entropy (DAG run, 7 tasks, 4 waves)**
- Task 1: CausalDAG ETS Store (Section 3.1) -- worker-1 (opus)
- Task 2: DAG Query API & Pruning (Section 3.2) -- worker-2 (sonnet)
- Task 3: Canvas Topology Renderer (Section 3.3) -- worker-3a (haiku scaffold) + worker-3b (sonnet refine)
- Task 4: EntropyTracker Sliding Window (Section 3.4) -- worker-4 (opus)
- Task 5: Entropy Alerting & Severity (Section 3.5) -- pre-satisfied by worker-4's comprehensive work
- Task 6: Entropy PubSub & SchemaInterceptor Integration (Section 3.6) -- worker-6 (sonnet)
- Task 7: Final migration + full test suite -- lead verified
- 113 tests, 0 failures, zero warnings
- Team: dag-phase3 (archived)

### New Files Created
| File | Purpose |
|------|---------|
| `lib/observatory/mesh/causal_dag.ex` | ETS-backed DAG GenServer (~329 lines) -- Node struct, per-session tables, orphan buffer, cycle prevention, broadcast_delta |
| `lib/observatory/gateway/entropy_tracker.ex` | Sliding window entropy GenServer (222 lines) -- record_and_score/2, 3-tier severity, EntropyAlertEvent, runtime config |
| `lib/observatory/gateway/topology_builder.ex` | DAG-to-topology bridge GenServer -- subscribes to session DAG deltas, publishes to gateway:topology |
| `assets/js/hooks/topology_map.js` | Canvas topology renderer -- force-directed layout, 6 node state colors, zoom/pan, edge click |
| `test/observatory/mesh/causal_dag_test.exs` | 19 tests |
| `test/observatory/gateway/entropy_tracker_test.exs` | 39 tests (unit + integration) |
| `test/observatory/gateway/topology_builder_test.exs` | 3 tests |

### Modified Files
| File | Change |
|------|--------|
| `lib/observatory/gateway/schema_interceptor.ex` | Added validate_and_enrich/1 (entropy overwrite), deduplicate_alert/2 |
| `assets/js/app.js` | Registered TopologyMap hook |
| `test/observatory/gateway/schema_interceptor_test.exs` | Added integration tests |

### Architecture Notes
- CausalDAG: ETS per-session tables, 30s orphan buffer, ancestor-chain cycle prevention, delta broadcasts on "session:dag:{session_id}"
- EntropyTracker: private ETS, sliding window of 5 tuples, uniqueness ratio, LOOP (<0.25) / WARNING (0.25-0.50) / Normal (>=0.50)
- TopologyBuilder: subscribes per-session via subscribe_to_session/1, publishes to "gateway:topology"
- Canvas: force-directed layout (repulsive F=500/d^2, spring F=(d-80)*0.01, 10px cap), 6 ADR-016 node colors
- SchemaInterceptor now calls EntropyTracker.record_and_score/2 synchronously, overwrites cognition.entropy_score

### Experiment: Haiku+Sonnet Pair (EXP-001)
- Task 3 used two-stage: haiku scaffolded files fast, sonnet refined
- Result: INCONCLUSIVE -- stage-2 prompt was too generic, sonnet spent time reading instead of refining
- Lesson: pre-digest spec details in sonnet prompt, don't just say "read the spec"
- Logged in PIPELINE_EXPERIMENTS.md

### Previous Milestones
- Phase 2: Gateway Core (5 tasks, 65 tests) -- commit pending
- Phase 1: DecisionLog Schema (4 tasks, 36 tests) -- commit 2a10e77
- Mode C Pipeline: 7 FRDs -> 5 phases, 24 sections, 77 tasks, 225 subtasks
- Mode B Pipeline: 12 ADRs -> 6 FRDs -> 79 UCs
- Phase 3 Gate Validation: 5 amendments, MONAD_LESSON_LOG.md with 5 lessons

### Artifacts
- MONAD_LESSON_LOG.md -- 5 lessons on upstream Monad Method leaks (pending evaluation)
- PIPELINE_EXPERIMENTS.md -- experiment log (EXP-001 + backlog)
- SPECS/checkpoints/1771771271-checkpoint.md -- Phase 3 pre-DAG gate checkpoint
- SPECS/conversations/CONV-003-phase3-gate-validation.md -- gate validation decisions
- ~/.claude/rules/rule-skill-coordinator.md -- outer coordinator protocol (new)

### Next Steps
- [ ] Phase 4 (next implementation phase)
- [ ] Code quality review of Phase 3 output (EntropyTracker O(1) deviation noted)
- [ ] EXP-002: haiku+sonnet with pre-digested stage-2 prompt
- [ ] Visual verification: open browser, test topology renderer
- [ ] MONAD_LESSON_LOG.md evaluation for upstream skill amendments

## Architecture Reminders

- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> Ash.create + PubSub -> LiveView
- Zero warnings: `mix compile --warnings-as-errors`
- Module size limit: 200-300 lines max
- embed_templates pattern: .ex (logic) + .heex (templates)
