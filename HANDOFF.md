# ICHOR IV - Handoff

## Current Status: Major Codebase Quality Overhaul (2026-03-19)

### Session Summary

Two-session codebase overhaul covering architecture, messaging, signals, performance, dead code, and Ash idiom fixes. The codebase is significantly cleaner, faster, and more maintainable.

### Completed

1. **MessageRouter** -- 10 messaging paths -> 1 single `send/1` API
2. **ichor_contracts** -- Facade + behaviour + config dispatch for Signals
3. **Signal wiring** -- 13 resources via FromAsh notifier, 9 GenServer/LiveView emissions, 5 broken subscribers fixed
4. **StreamEntry struct** -- Common type for signal livefeed with per-signal formatting
5. **Performance** -- 8 hot-path ETS/Enum fixes (select_delete, single-pass reduces)
6. **Dead code** -- 21 modules deleted, 20+ dead functions, 410 -> 387 files
7. **Supervisors** -- 4 -> 2 (SystemSupervisor + ObservationSupervisor)
8. **Notes** -- GenServer demoted to plain ETS module
9. **Ash DSL** -- 4 manual changeset fns replaced with set_attribute(arg(...)), redundant identity removed
10. **Banners** -- 255 decorative comments removed
11. **Credo** -- All issues resolved, zero remaining
12. **Safety** -- String.to_atom on HTTP input, Ash NotLoaded guards, struct truncation

### Audit Results (Research Complete, Implementation Pending)

**Ash code_interface centralization** (saved to memory/project/ash_code_interface_audit.md):
- Genesis domain only wraps Node, 9 sub-resources accessed directly by AgentTools (HIGH)
- LiveView calls Mes.Project directly (HIGH)
- Workshop.Persistence bypasses Workshop domain (HIGH)

**Ash enum candidates** (saved to memory/project/ash_enum_candidates.md):
- 11 inline one_of lists should be Ash.Type.Enum

**AgentWatchdog merge** (codex design complete):
- heartbeat + agent_monitor + nudge_escalator + pane_monitor -> 1 GenServer + 3 pure helpers

**User's latest question**: Do all validations/calculations/transforms/aggregations/changes/actions/preparations follow the Ash docs examples from `mix usage_rules.search_docs`? The macro audit found 4 HIGH violations (already fixed) but a comprehensive docs-driven audit has not been done.

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix credo --strict` -- CLEAN (0 issues)
- File count: 387 (was 410)
- Top-level modules: 26 (was 31)

### What's Next (Priority Order)
1. Ash code_interface centralization (extend Genesis, Mes, Workshop domains)
2. Ash.Type.Enum extraction (11 candidates)
3. AgentWatchdog merge (4 GenServers -> 1 + 3 helpers)
4. Comprehensive Ash DSL audit against usage_rules docs
5. @spec coverage on remaining functions
6. E2E test: Build PulseMonitor
