# ICHOR IV - Handoff

## Current Status: Code Quality + Signals Audit Complete (2026-03-19)

### Session Summary

Major session covering architecture, messaging consolidation, code quality, and signals coverage audit.

### Completed This Session

1. **DAG Build on standalone Mix libraries** -- Workers build in `subsystems/{name}/`, not host app
2. **ichor_contracts shared library** -- Facade + behaviour + config dispatch for Signals
3. **Signal system split** -- Signals (facade) + Runtime (host impl) + Domain (Ash)
4. **Catalog split** -- 550L -> 5 bounded modules + 76L aggregator
5. **MessageRouter** -- Single delivery authority replacing 10 redundant messaging paths
6. **Credo cleanup** -- All 71+17 issues fixed, zero remaining
7. **Banner removal** -- 255 decorative comment banners removed across 71 files
8. **send_message arity fix** -- Critical bug: Messaging called send_message/3 but AgentProcess only had /2
9. **REFACTOR.md** -- Deep analysis for all 13 umbrella apps
10. **Parameter ordering rule** -- Dispatch params first, unused last

### Audit Results (Research Complete, Not Yet Implemented)

**Signals bypass audit** -- 37 actions bypass the Signal stream:
- 15 HIGH: DAG run lifecycle, Genesis pipeline gates, MES transitions, agent eviction, Channels shadow layer
- 14 MEDIUM: All Genesis artifacts, Fleet team ops, HITL approve/reject
- 8 LOW: Workshop canvas, blueprint CRUD

**@spec/@doc audit** -- Systemic gap:
- 1,149 public functions missing @spec across 158 files
- 400+ public functions missing @doc across 136 files
- 11 modules missing @moduledoc

**Ash AI article** -- Key takeaway: Ash constraint system is primary for LLM type exposure, not @spec. Action `description` strings are load-bearing for MCP tools.

### Architecture Decisions

- **MessageRouter**: Plain module (Iron Law: no process needed). One `send/1` API.
- **ichor_contracts**: Facade + behaviour + config dispatch. Host configures `:signals_impl`.
- **Subsystem boundary**: Workers FORBIDDEN from touching host files. Jobs referencing host files get failed.
- **Parameter ordering**: Dispatch params first, accumulators first in recursion, unused last.
- **@spec policy**: Required on public API functions. Skip GenServer callbacks, Ash DSL anonymous fns.
- **No decorative banners**: No `# ═══` or `# ── Label ──`. Use @doc and module structure.

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- CLEAN (0 issues)

### What's Next (Priority Order)
1. Wire missing signals (15 HIGH items from audit)
2. Add @spec to highest-impact modules (MessageRouter, Dag, Fleet, Genesis domains)
3. E2E test: Build PulseMonitor with new boundary enforcement
