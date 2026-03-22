# ICHOR IV - Handoff

## Current Status: SIGNALS DOMAIN REFACTOR (2026-03-22)

Forensic audit of `lib/ichor/signals/` complete. Ready to execute wave-based refactor.

### Session Summary

1. **Bug fix** (done): `AgentState.maybe_inbox/2` backend-nil guard broke MCP inter-agent messaging for all tmux-backed teams. Fixed + bounded inbox at 200. Commits: `695e108`, `46d0cd5`.

2. **Forensic audit** (done): Full boundary, function shape, coupling graph, and PubSub/Archon analysis of `lib/ichor/signals/`. Written to `docs/audits/2026-03-22-signals-domain-forensics.md`.

3. **DAG PR merged**: `SPECS/dag/AGENT_PROMPT_DAG.md` + `.yml` + `.dot` + `.ex` -- decision framework as traversable DAG.

4. **Wave-based refactor** (next): Same pattern as 2026-03-21 architecture audit.

### Audit Key Findings

- Only ~40% of `lib/ichor/signals/` is signal infrastructure. Rest is monitoring, health, projections, gateway validation.
- 3 misplaced modules: AgentWatchdog (6 cross-domain imports), SchemaInterceptor (Mesh concern), ProtocolTracker (monitoring)
- 7 boundary smells: Operations, EntropyTracker, EventStream, Buffer, TaskProjection, ToolFailure, HITLInterventionEvent
- `classify_and_store/8` in EntropyTracker is a shape smell (8 params, 3 mixed concerns)
- EventStream mixes 3 concerns: event buffer + heartbeat registry + ingest pipeline

### Architect Directives

- "events == signals, signals == topics" -- naming is confused
- "schema interceptor should not contain the word entropy at all"
- HITL intervention event is misplaced
- Handler behaviour dispatches at emit-time in the Signals facade
- Don't extract more from AgentWatchdog -- already has sub-modules
- "Enrichment" is a code smell
- Follow the wave pattern from 2026-03-21

### Next: Create tasks.jsonl waves

Priority sequence:
- **Wave 1**: Handler behaviour + catalog split into catalog/ + SignalManager split into signal_manager/
- **Wave 2**: EntropyTracker.Healer (first handler implementation) + SchemaInterceptor boundary fix
- **Wave 3**: Module relocations (AgentWatchdog, ProtocolTracker, HITL, etc.)
- **Wave 4**: Quality sweep (naming, dead specs, shape fixes)

### Key Files

- `docs/audits/2026-03-22-signals-domain-forensics.md` -- full audit
- `SPECS/dag/AGENT_PROMPT.md` -- refactor decision framework
- `SPECS/dag/AGENT_PROMPT_DAG.md` -- DAG traversal guide
- `~/.claude/plans/lovely-wondering-bengio.md` -- plan file (needs rewrite for wave approach)
- `memory/project/archon_entropy_healing.md` -- design requirements

### Build
- `mix compile --warnings-as-errors`: CLEAN
- Last test run: 314 Ash resource tests, 0 failures
