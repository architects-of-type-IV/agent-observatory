# Observatory - Handoff

## Current Status: Mode B Complete + Feed Redesign (2026-02-21)

### Just Completed

**Mode B Pipeline (Monad Method: Define)**
- Ran full 4-stage pipeline with parallel agents
- 12 accepted ADRs -> 6 FRDs (79 FRs) -> 79 UCs with Gherkin scenarios
- Gate 1: FAIL (2 frontmatter source_adr mismatches), fixed, re-validated PASS
- Gate 2: PASS (18 minor Gherkin-AC mapping notes, non-blocking)
- Checkpoint: `SPECS/checkpoints/1740153600-checkpoint.md`
- All artifacts committed (88 files)

**Decision-Log Skill Updates**
- Added Write/Edit tools to allowed-tools
- Phase 4 now produces proper ADR files (YAML frontmatter + References + Key Moments) + Conversation artifacts + INDEX.md
- Output directory changed to `SPECS_HARVESTED/` (machine-generated artifacts separate from hand-authored SPECS)
- Observatory uses `SPECS/` directly (no hand-authored specs to conflict with)

**Feed Redesign: Turn-Based Architecture (tasks 1-13 DONE)**
- Replaced segment-based feed with turn-based conversation grouping
- `build_turns/1` splits events by UserPromptSubmit/Stop boundaries
- `classify_tool/1` categorizes tools: research/build/verify/delegate/communicate/think/other
- `group_into_phases/1` groups consecutive same-category tool pairs
- Inverted collapse: `expanded_sessions` (collapsed by default, active auto-expand)
- New templates: `conversation_turn.html.heex`, `activity_phase.html.heex`
- Old templates moved to trash: `parent_segment.html.heex`, `subagent_segment.html.heex`
- ToolChain multi-tool path removed (phases handle grouping now)

### In Progress
- Task 14: Runtime verification of feed view (visual check needed)

### Key Files Changed (Feed Redesign)
| File | Change |
|------|--------|
| `dashboard_feed_helpers.ex` | Rewritten: build_turns, classify_tool, group_into_phases |
| `dashboard_live.ex` | expanded_sessions replaces collapsed_sessions, expand_all/collapse_all |
| `feed_view.ex` | attr expanded_sessions |
| `session_group.ex` | Turn dispatch + phase_label/phase_color helpers |
| `session_group.html.heex` | Renders turns instead of segments |
| `conversation_turn.html.heex` | NEW: turn header + response preview + phases |
| `activity_phase.html.heex` | NEW: phase icon/color + tool summary + expandable tools |

### SPECS Artifacts
```
SPECS/
  _templates/          # Copied from memories project
  decisions/           # 12 ADRs + INDEX.md
  conversations/       # 3 CONV files
  requirements/
    frds/              # FRD-001 through FRD-006
    use-cases/         # UC-0001 through UC-0158 (79 files)
    mode-b-plan.md
    gate-1-report.md
    gate-2-report.md
  checkpoints/         # 1740153600-checkpoint.md
```

### Remaining
- [ ] Task 14: Visual verification of feed view
- [ ] Visual verification: all other views
- [ ] Test feed with active agents spawning subagents
- [ ] Test DAG rendering with real pipeline running
- [ ] Remove dead ToolExecutionBlock module + delegate

## Architecture Reminders

- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> Ash.create + PubSub -> LiveView
- Zero warnings: `mix compile --warnings-as-errors`
- Module size limit: 200-300 lines max
- embed_templates pattern: .ex (logic) + .heex (templates)
