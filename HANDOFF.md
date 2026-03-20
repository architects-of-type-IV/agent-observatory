# ICHOR IV - Handoff

## Current Status: Session Complete (2026-03-20)

### Summary
Massive simplification session. 228 → 127 files. All 5 phased plan phases complete. Build/credo/dialyzer clean.

### What Was Done
1. All 5 simplification phases (wrappers, events, runners, tools, memory)
2. 37 audit findings fixed
3. Level 1+2 module reduction (child folding + domain consolidation)
4. 9 Ash resources collapsed (5 artifacts→1, 4 roadmap→1, 4 blueprints→1)
5. Zombie module cleanup (old spawners, builders, gateway router)
6. Observation stack consolidation (TopologyBuilder→EventBridge)
7. Archon Chat 5→1, Tasks 3→2
8. EventBuffer + HeartbeatManager absorbed into Events.Runtime
9. Control wrappers fully inlined (lookup, runtime_query, runtime_view)
10. Oban installed (SQLite, 5 queues)
11. All team prompts unified (READY handshake protocol)
12. MES fixes (duplicate brief guard, scheduler tick, spawn bugfix)
13. UI improvements (transport badge, message dedup, sidebar, ANSI rendering)
14. Comprehensive docs: 5 page feature docs, annotated TREE.md, redesign blueprint

### Build
- `mix compile --warnings-as-errors` CLEAN
- `mix credo --strict` CLEAN
- Server starts on 4005

### File Count: 127 (target ~55-60)

### Key Documentation
- `docs/plans/2026-03-20-1430-redesign-blueprint.md` -- combined architect+codex vision for target state
- `docs/plans/2026-03-20-1354-target-structure.md` -- codex target folder structure
- `docs/plans/2026-03-20-1354-audit-simplify.md` -- codex round 3 audit
- `docs/pages/*.md` -- comprehensive feature docs for all 5 pages
- `lib/ichor/TREE.md` -- annotated module tree

### Next: Redesign Phase
The remaining reduction (127→~55) requires redesign, not folding:
- Vertical slices aligned to Ash Domains
- Fleet = Workshop (agents, teams, blueprints, prompts, launcher)
- Prompts belong to fleet, not projects
- Ash config over code: 90% should be declared in DSL
- Delete ephemeral Ash resources → plain query modules
- Move signals contracts from ichor_contracts into main app
- 6 boundaries: events, fleet, projects, memory, transport, tools
