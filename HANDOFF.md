# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Ash-Disciplined Refactor (Phases 1-7 Complete) (2026-03-08)

### Just Completed: Phase 6 -- EventController Extraction

Extracted all business logic from EventController (277 -> 66 lines, -211 lines). Controller is now a thin HTTP adapter.

**What moved where:**
- `sanitize_payload/1` + `truncate_tool_input/1` -> `EventBuffer.ingest/1` (sanitizes before storage)
- `compute_duration/2` + `@tool_start_table` ETS + `init_tool_tracking/0` -> `EventBuffer` (tool duration tracking)
- `estimate_cost_cents/4` + `maybe_record_token_usage/2` -> `Costs.CostAggregator.record_usage/2`
- `handle_channel_events/1` + `handle_pre_tool_use/1` + `handle_send_message/2` + `ensure_team_supervisor/1` -> `Gateway.Router.ingest/1`

### Prior: Phases 1-5, 7

Executed 6 of 8 phases from the approved refactor plan. Net -730 lines from web layer, domain logic moved into Fleet/Activity modules.

- **Phase 1**: Dead code deletion (-197 lines from 3 helper modules)
- **Phase 2**: Canonicalize role classification (AgentRegistry.derive_role as source of truth)
- **Phase 3**: Unified agent index (Fleet.Agent attrs + LoadAgents merge + thin lookup)
- **Phase 4**: Sessions/inspector/topology -> Fleet.Queries module
- **Phase 5**: Tool analytics/timeline -> Activity.EventAnalysis module
- **Phase 7**: Template layer violations fixed (paused_sessions + mailbox as assigns)

### Remaining Phase
- **Phase 8**: ICHOR IV rename (each rename should be own commit per plan)

### Key Files Modified (Phase 6)
- `lib/observatory_web/controllers/event_controller.ex` -- thin HTTP adapter (66 lines)
- `lib/observatory/event_buffer.ex` -- now owns sanitization + duration tracking (206 lines)
- `lib/observatory/gateway/router.ex` -- now owns channel side effects (244 lines)
- `lib/observatory/costs/cost_aggregator.ex` -- now owns token usage recording (182 lines)

### Build Status
`mix compile --warnings-as-errors` clean.
