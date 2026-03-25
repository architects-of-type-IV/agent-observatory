# ICHOR IV - Handoff

## Current Status: DEEP CLEANUP SESSION (2026-03-25)

260 .ex files, ~24k lines. Build clean. Tests deleted (stale against dissolved APIs).

### What Was Done This Session

**Phase 1: Single-use module inlining (a9f4ac6)**
- 9 modules deleted, logic inlined at callsites (-208 lines)
- SyncRunner, 4 Ash enum types, AgentLookup, DateUtils, SessionEviction, TeamPreset
- 7 dead public functions removed across EntropyTracker, EscalationEngine, EventStream, ProtocolTracker

**Phase 2: Dead subsystem removal (f20ac4b)**
- Mesh subsystem trashed: CausalDAG, EventBridge, DecisionLog, Mesh.Supervisor (~870 lines)
- SchemaInterceptor, GatewayController, gateway renderer trashed
- GenStage pipeline remnants: Events domain, Ingress, Projector infrastructure (Supervisor/Behaviour/Router/Signal/SignalHandler/SignalProcess)
- Signals indirection: Behaviour, Noop, Event, configurable impl() pattern
- Fleet domain: Fleet.Session, Fleet.Supervisor, Fleet.Preparations.LoadSessions
- bridge_to_events dual-emit path in Signals.Runtime
- FromAsh notifier stubbed (compile target only)
- HITL renderer extracted from deleted gateway renderer
- Total: 37 files, -1980 lines

**Phase 3: Plugin behaviour removal (66590ff)**
- Ichor.Plugin behaviour + Ichor.Plugin.Info struct deleted (-124 lines)
- Zero implementors in repo; MES plans plugins but runtime contract was never wired
- Empty mesh/ and protocol_components/ directories cleaned up

**Phase 4: Test removal (eeb769c)**
- 11 test files deleted (-2220 lines)
- All 13 failures were pre-existing (Ash MustBeAtomic + UUID cast errors from prior refactors)
- test_helper.exs kept

**Phase 5: Documentation update (a212f88)**
- 10 docs updated to remove stale Mesh/GenStage/Fleet/Plugin references
- TREE.md, architecture docs, diagrams, BRAIN.md, REFACTOR.md

### Session Total
~4,700 lines removed across 5 commits.

### Build Status
- `mix compile --warnings-as-errors`: CLEAN
- `mix test`: 0 tests (all removed, fresh tests needed post-refactor)

### Known Diagnostics (pre-existing, not from this session)
- `Ichor.Signals.Runtime` functions show as undefined in LSP (compilation order)
- `Ichor.Signals.EventStream` functions undefined in controllers
- `Ichor.Infrastructure.HITLRelay` functions undefined in hitl_controller

### Remaining Work
- **SIG-7**: Handler behaviour + facade dispatch
- **SIG-8**: Split catalog into catalog/
- **Wave 2**: Entropy handler + SignalManager split
- **Wave 3**: Module relocations
- **Wave 4**: Specs, types, structs
- **ADR-026**: `use Ichor.Signal` macro, `Ichor.Signals.Memories.*` modules
- **Diagnostics**: Fix undefined function warnings in controllers + signals.ex
