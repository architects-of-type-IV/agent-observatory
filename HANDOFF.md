# ICHOR IV - Handoff

## Current Status: SIGNALS WAVE 1 IN PROGRESS (2026-03-22)

### Session Summary

1. **Bug fix**: AgentState inbox for tmux-backed agents. Commits: `695e108`, `46d0cd5`.
2. **Forensic audit**: Full signals domain audit -> `docs/audits/2026-03-22-signals-domain-forensics.md`
3. **Blueprint**: Shape-first refactor plan -> `docs/plans/2026-03-22-signals-refactor-blueprint.md` (v3)
4. **Wave 1 execution**: SIG-1 through SIG-6 completed. SIG-7, SIG-8 remaining.

### What Was Done (Wave 1 shape fixes)

**entropy_tracker.ex** (SIG-1/2/3/4):
- `classify_and_store/8` decomposed into `classify/3` (pure) + `emit_state_change/4` (side effect) + inline ETS store
- `build_alert_event/4` inlined (was misnamed, 2 unused params)
- `slide_window` uses `tl()` not `List.delete_at`
- Dead spec removed, config read once in `init`
- Subscribes to `:events`, scores from `handle_info(:new_event)` using `{tool_name, hook_event_type}` tuple
- `lookup_session/3` extracted as shared pure function
- Score is pure, store is side effect -- separate operations, not one chimera

**schema_interceptor.ex** (SIG-4): All entropy references removed. Pure validation only.

**event_bridge.ex** (SIG-4): `maybe_register_agent` and `maybe_enrich_entropy` removed. Unused aliases cleaned.

**event_stream.ex** (SIG-5): `AgentEntry.uuid?` replaced with inline regex. `tombstoned?/1` is pure predicate. Tombstone sweep added to heartbeat timer. `emit_intercepted` variants merged.

**protocol_tracker.ex** (SIG-6): 3 identical trace clauses merged into `build_trace/2` + `trace_fields/2`.

### Remaining Wave 1

- **SIG-7**: Create handler.ex behaviour + facade dispatch
- **SIG-8**: Split catalog.ex into catalog/

### Architect Directives (critical, from this session)

- **Refactoring = gardening. Every day, water a little.**
- **Refactoring = shaping to generics until you see mirrors/twins.**
- **Naming is what you do last when there is no other choice.**
- **Signals = PubSub. That's it.** Emit, subscribe, act.
- **You either score or store.** Pure functions separated from side effects.
- **No OOP/DDD language.** No "domains", "bounded contexts", "authority models."
- **Don't invent names.** No "Healer", "EntropyHealer". Shape the code first.
- **Ask: can I rearrange arities and see a stdlib function?**
- **Ask: why do we store in a flowing system?**
- **Ask: is protocol tracker tracking or matching?**

### Key Files

- `docs/plans/2026-03-22-signals-refactor-blueprint.md` -- shape-first refactor plan
- `docs/audits/2026-03-22-signals-domain-forensics.md` -- forensic audit
- `memory/feedback/shape_first_refactoring.md` -- how to approach refactoring
- `memory/feedback/refactoring_philosophy.md` -- gardening, generics, naming last

### Build
- `mix compile --warnings-as-errors`: CLEAN
