# Plan Validation Report

**Generated:** 2026-03-19
**Method:** File existence checks, grep verification, git log cross-reference

---

## Summary Table

| Plan | Status | Evidence | Action Needed |
|------|--------|----------|---------------|
| 2026-03-13-registry-redesign-design.md | PARTIALLY DONE | AgentRegistry ETS GenServer deleted; `agent_entry.ex` kept; `AgentProcess.list_all/lookup/update_field` wired; `fleet_changed` signal in catalog. Still: 15 files reference `AgentRegistry` (dashboard handlers, fleet_helpers, event_buffer, memories_bridge, agent_watchdog, output_capture, router) -- migration Tasks 5, 6, 7 not confirmed complete | Remove all remaining `AgentRegistry` references; verify fleet sidebar reactive |
| 2026-03-13-registry-redesign.md | PARTIALLY DONE | Same evidence as design doc above. Tasks 1-4 largely done. Tasks 5 (batch consumer migration), 6 (delete ETS files), 7 (reactive dashboard subscribe) partially done -- 15 files still import `AgentRegistry` | Complete Tasks 5-7; run grep verification step from Task 6 |
| 2026-03-15-genesis-nodes-design.md | COMPLETED | All 10 resources exist as `Ichor.Projects.*` (Adr, Feature, UseCase, Checkpoint, Conversation, Phase, Section, Task, Subtask, Node); Node has `belongs_to :mes_project`; MCP tools present in Tools domain; MES factory view shows pipeline; Mode A E2E smoke test committed (`9eefe41`, `483bd9e`) | None -- design fully realized under 4-domain model |
| 2026-03-17-mes-unified-design.md | COMPLETED | Marked **IMPLEMENTED** in file header; `mes_factory_components.ex` and `mes_artifact_components.ex` exist; `pipeline_stage.ex` exists under `lib/ichor/projects/`; `genesis_sub_tab` wired in mes_components.ex and dashboard handlers; `genesis_switch_tab` / `genesis_select_artifact` events in `@mes_events` list; committed in `9eefe41` and `483bd9e` | None |
| 2026-03-17-genesis-mode-a-smoketest.md | COMPLETED | Mode A smoke test fixes committed (`9eefe41`); Mode A E2E committed (`483bd9e`); RunProcess lifecycle implemented; ADR resources exist in DB; pipeline_stage derivation live | None -- smoke test ran and produced fixes |
| 2026-03-17-genesis-tab-design.md | SUPERSEDED | Design described a separate "Genesis" tab in the MES tab switcher. The unified factory view (`2026-03-17-mes-unified-design.md`) absorbed this -- artifact browsing is now inline in the factory view via `genesis_sub_tab` (Decisions/Requirements/Checkpoints/Roadmap tabs) rather than a separate top-level MES tab | No action -- superseded by the unified factory view |
| 2026-03-17-genesis-tab-plan.md | SUPERSEDED | Implementation plan for the separate Genesis tab. The unified design (`mes-unified-design.md`) replaced this approach. `genesis_tab_components.ex` was never created; instead `mes_factory_components.ex` + `mes_artifact_components.ex` were created. The sub-tab structure was preserved but integrated differently | No action -- superseded |
| 2026-03-18-umbrella-architecture.md | SUPERSEDED | The umbrella was created (git history shows extraction of ichor_activity, ichor_events, ichor_genesis, ichor_mes, ichor_fleet, ichor_workshop, ichor_memory_core, ichor_mesh), then collapsed back into a single app. `apps/` dir exists with only an empty `apps/ichor/lib/ichor/` scaffold. The de-umbrella roadmap superseded this plan | No action -- umbrella approach abandoned in favor of in-process 4-domain model |
| 2026-03-18-module-classification.md | SUPERSEDED | Classification was used as input for the umbrella extraction waves, which were then reversed. The 4-domain consolidation (`domain-consolidation.md`) replaced the per-app classification as the organizing principle. Current file structure (`lib/ichor/control/`, `lib/ichor/projects/`, `lib/ichor/observability/`, `lib/ichor/tools/`) reflects the 4-domain model, not the umbrella classification | No action -- approach superseded |
| 2026-03-19-de-umbrella-roadmap.md | COMPLETED | The umbrella was fully collapsed back into a single app. Git shows: `41ed20f` (flatten apps/ichor to root), `f98d6a5` (clean up consolidation artifacts), `f3d48cc` (quality checkpoint). `apps/ichor/lib/ichor/` is an empty directory stub. Physical file reorganization to 4-domain structure committed in `34fe9ee`. Merge-back order followed (events -> activity -> memory_core -> mesh -> genesis -> mes -> fleet -> workshop) | Clean up empty `apps/ichor/lib/ichor/` stub directory |
| 2026-03-19-domain-consolidation.md | COMPLETED | All 5 phases executed: `Ichor.Observability` (`152595d`), `Ichor.Control` (`7c01245`), `Ichor.Projects` (`531cffd`), `Ichor.Tools` (`52eeebd`), module inlining (`33e53fa`, `f814d84`). Domain modules confirmed: `control.ex`, `projects.ex`, `observability.ex`, `tools.ex`. Physical file reorg committed in `34fe9ee`. Old directories (`fleet/`, `genesis/`, `mes/`, `dag/`) contain 0 `.ex` files | None -- domain consolidation complete |
| 2026-03-19-ash-ai-tool-scoping.md | COMPLETED | `Ichor.Tools.Profiles` module exists at `lib/ichor/tools/profiles.ex`. Tool Profiles committed in `09ea350` ("feat(tools): add Tool Profiles for MCP scoping, extract 6 Ash.Type.Enums"). This is a research document whose primary recommendation (Pattern 2: Tool profile module attributes) was implemented | None |
| 2026-03-19-quality-audit.md | PARTIALLY DONE | `@doc`/`@spec` sweep committed (`c6a87cf`). `@enforce_keys` partially added: `RunProcess` has `[:run_id, :tmux_session]`, `AgentProcess` has `[:id, :role, :status]`, `TeamSupervisor` has `[:name]`. Banner comments partially removed: `control.ex` and `agent_watchdog.ex` banners may be gone, but `fleet_helpers.ex` (5 banners), `dashboard_archon_handlers.ex` (1 banner), `projects/validator.ex` (1 banner) still have banners. `@moduledoc` gaps in ichor_web/ likely addressed in doc sweep | Remove 7 remaining banner comments; verify remaining `@enforce_keys` gaps (genesis/RunProcess, mes/RunProcess, mesh/CausalDag.Node, memories_client structs) |
| 2026-03-19-component-library-research.md | NOT STARTED | Research produced clear recommendations (badge + pill_button primitives, no external lib). No `IchorWeb.Components.Ichor.Primitives` module found. `badge/1` and `pill_button/1` components not created. `badge_class/1` in `fleet_helpers.ex` is still a role-specific function not the generic variant component | Implement `badge/1` and `pill_button/1` primitive components per research recommendations |
| 2026-03-19-merge-back-gates.md | COMPLETED | This is a process/checklist document, not an implementation plan. The umbrella was collapsed (de-umbrella completed). The gate checklist is now a standing reference for if/when any future extraction happens. `mix ichor.boundary_audit` task exists | None -- standing process document |
| 2026-03-19-next-session-prompt.md | PARTIALLY DONE | Physical file reorganization completed (`34fe9ee`). Module namespaces updated to match 4-domain model. However: (1) RunProcess lifecycle consolidation (3 parallel implementations) not confirmed done -- `run_process.ex` files still exist in `projects/` directory; (2) component library primitives not started; (3) server restart/MES team relaunch is a runtime operation, not code | Complete RunProcess consolidation; implement component primitives |

---

## Status Key

- **COMPLETED**: All described changes implemented and committed.
- **PARTIALLY DONE**: Core work done, specific items remain.
- **NOT STARTED**: No evidence of implementation.
- **SUPERSEDED**: Plan replaced by a different approach that was implemented instead.

---

## Remaining Work Summary

### High Priority (blocking correctness)

1. **Registry redesign Tasks 5-7** -- 15 files still reference `AgentRegistry`. Fleet sidebar may not be fully reactive yet. Run: `grep -r "AgentRegistry" lib/ --include="*.ex"` and migrate each callsite.

### Medium Priority (code quality)

2. **Banner comments** (7 remaining) -- `fleet_helpers.ex` (5), `dashboard_archon_handlers.ex` (1), `projects/validator.ex` (1). These violate the standing ban.

3. **`@enforce_keys` gaps** (partially fixed, some remain) -- genesis `RunProcess`, mes `RunProcess` (need to verify current state), `mesh/CausalDag.Node`.

4. **RunProcess consolidation** -- 3 parallel implementations (dag, genesis, mes run_process) mentioned in next-session-prompt as deferred work.

### Low Priority (enhancement)

5. **Component library primitives** -- `badge/1` and `pill_button/1` components per research; ~165 lines of deduplication potential.

6. **Empty `apps/ichor/lib/ichor/` stub** -- left over from umbrella teardown, safe to remove.
