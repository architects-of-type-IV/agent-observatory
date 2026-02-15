# Observatory - Handoff

## Current Status: Messaging Reliability Analysis Complete

**Team**: messaging-analysis (3 agents: ui-analyst, protocol-analyst, reliability-analyst)
**Goal**: Analyze Observatory messaging pipeline for reliability, correctness, and architecture

## Analysis Complete (2026-02-15)

### 1. Form Refresh Bug (ui-analyst) - DIAGNOSED
**Root Cause**: `:tick` timer (1s) → `prepare_assigns()` → new `:teams` list → LiveView re-render → form DOM destroyed
**Recommended Fix**: Add `phx-update="ignore"` wrapper OR memoize teams computation

### 2. Message Reliability (reliability-analyst) - 6 ISSUES FOUND

**CRITICAL**:
1. **CommandQueue file accumulation** - 164 files (704KB) in ~/.claude/inbox/, never cleaned
   - Fix: Add CommandQueue.delete_command/2, call from mark_read
2. **Duplicate delivery** - Agent crash + restart = duplicate messages from disk
   - Fix: Track acknowledged IDs in persistent storage OR dedup by filename
3. **Message loss on restart** - ETS cleared before CommandQueue consumed
   - Fix: Read-through from CommandQueue on startup OR persist read state

**MEDIUM**:
4. **No ordering guarantees** - ETS/CommandQueue/PubSub are independent, no sequence numbers
5. **ETS memory growth** - Messages accumulate, no TTL cleanup
6. **Multi-tab identity confusion** - Dashboard session_id varies per tab

### 3. Protocol Analysis (protocol-analyst) - IN PROGRESS
Awaiting findings on message format, envelope structure, error handling

**Status**: 2/3 agents complete, awaiting protocol analyst final report

## Previous Work

### Dead Code Audit Results (Stage 5)
- Found (Stage 1): 23 instances across 4 scout areas
- False positives removed (Stage 2): 2 (short_model_name, Observatory module)
- Confirmed: 19
- Files edited: 11
- Files moved to tmp/trash/dead-code-audit/: 13
- Build: PASS (zero warnings)
- Remaining instances: 0

### Key Removals
1. **Unused Ash domains**: Removed Messaging, TaskBoard, Annotations from config.exs ash_domains
2. **Dead Ash files**: 6 files moved (messaging.ex, message.ex, task_board.ex, task.ex, annotations.ex, note.ex)
3. **Dead components**: 3 files moved (toast_container.ex, session_dot.ex, event_type_badge.ex)
4. **Dead PageController**: 3 files moved (page_controller.ex, page_html.ex, home.html.heex) + test
5. **Dead functions**: installed_extensions, poll_responses, get_pending_commands, remove_team_channel, add_search_to_history, filter_threads_by_participant, extract_participants, handle_edit_task
6. **Visibility fixes**: 3 functions changed def->defp (detect_tool_loops, group_events_by_session, pair_tool_events)
7. **Dead macro**: channel/0 removed from observatory_web.ex

### Pipeline Artifacts
- `.claude/audit-pipeline/1-scout-findings.md`
- `.claude/audit-pipeline/2-verified-findings.md`
- `.claude/audit-pipeline/3-execution-plan.md`
- `.claude/audit-pipeline/4-validation-report.md`

## Build Status
`mix compile --warnings-as-errors` -- PASSES (zero warnings)
