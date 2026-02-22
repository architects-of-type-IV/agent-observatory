# Observatory - Handoff

## Current Status: Phase 4 Gateway Infrastructure & HITL COMPLETE (2026-02-22)

### Just Completed

**Phase 4: Gateway Infrastructure & HITL (DAG run, 7 tasks, 6 waves)**
- Task 1: HeartbeatManager GenServer + CapabilityMap (Section 4.1) -- worker-1 (opus)
- Task 2: CronScheduler & DB Schema (Section 4.2) -- worker-2 (opus)
- Task 3: WebhookRouter Retry & DLQ (Section 4.3) -- worker-3 (opus)
- Task 4: HITLRelay State Machine (Section 4.4) -- worker-4 (opus, parallel)
- Task 5: HITL HTTP Endpoints & Auth (Section 4.5) -- worker-5 (opus, parallel)
- Task 6: Auto-Pause & Operator Actions (Section 4.6) -- worker-6 (opus)
- Task 7: Final migration + test suite -- worker-7 (sonnet)
- 204 tests, 0 failures, zero warnings
- Team: dag-phase4 (archived)
- Commit: eba293d

### New Files Created (13 modules)
| File | Purpose |
|------|---------|
| `lib/observatory/gateway/capability_map.ex` | Real GenServer tracking agent capabilities (register/remove/get/list) |
| `lib/observatory/gateway/heartbeat_manager.ex` | GenServer with 90s eviction, 30s check loop |
| `lib/observatory/gateway/heartbeat_record.ex` | Ecto schema for gateway_heartbeats table |
| `lib/observatory/gateway/cron_job.ex` | Ecto schema for cron_jobs table |
| `lib/observatory/gateway/cron_scheduler.ex` | GenServer with schedule_once/3, DB recovery |
| `lib/observatory/gateway/webhook_delivery.ex` | Ecto schema for webhook_deliveries table |
| `lib/observatory/gateway/webhook_router.ex` | GenServer with 5-stage exponential backoff, HMAC-SHA256, DLQ |
| `lib/observatory/gateway/hitl_events.ex` | GateOpenEvent/GateCloseEvent structs |
| `lib/observatory/gateway/hitl_relay.ex` | Per-session pause/unpause state machine with ETS buffer |
| `lib/observatory/gateway/hitl_intervention_event.ex` | Ecto schema for audit trail |
| `lib/observatory/plugs/operator_auth.ex` | Plug for x-observatory-operator-id header validation |
| `lib/observatory_web/controllers/heartbeat_controller.ex` | POST /gateway/heartbeat |
| `lib/observatory_web/controllers/hitl_controller.ex` | 4 HITL endpoints (pause/unpause/rewrite/inject) |
| `lib/observatory_web/controllers/webhook_controller.ex` | POST /gateway/webhooks/:webhook_id |
| `lib/observatory_web/live/session_drilldown_live.ex` | Operator approve/reject/rewrite actions |

### Modified Files
| File | Change |
|------|--------|
| `lib/observatory/application.ex` | Added CapabilityMap, HeartbeatManager, CronScheduler, WebhookRouter, HITLRelay to supervisor |
| `lib/observatory_web/router.ex` | Added heartbeat, webhook, HITL routes in /gateway scope + :hitl_auth pipeline |
| `lib/observatory/gateway/schema_interceptor.ex` | Added maybe_auto_pause/1, maybe_schedule_reminder/1 |

### Migrations (4)
- `20260222170000_create_webhook_deliveries.exs`
- `20260222180000_create_hitl_intervention_events.exs`
- `20260222200000_create_gateway_heartbeats.exs`
- `20260222210000_create_cron_jobs.exs`

### Architecture Notes
- HeartbeatManager: 30s `:check_heartbeats` timer, 90s eviction threshold, calls CapabilityMap.remove_agent/1
- CapabilityMap: GenServer with map state %{agent_id => %{capabilities, cluster_id, registered_at}}
- CronScheduler: schedule_once/3 with DB persistence, Process.send_after timers, startup recovery from Repo
- WebhookRouter: 5s poll, exponential backoff [30, 120, 600, 3600, 21600]s, HMAC-SHA256 via :crypto, DLQ on "gateway:dlq"
- HITLRelay: ETS :ordered_set :hitl_buffer, per-session %{session_id => :normal | :paused}, ordered flush on unpause
- HITL endpoints: OperatorAuth plug extracts operator_id, HITLInterventionEvent audit trail per action
- SchemaInterceptor: auto-pause when control.hitl_required == true, buffer triggering DecisionLog

### Experiment: Parallel Code Review Agent (EXP-002)
- Wave 4 (tasks 4 & 5 parallel): spawned Explore agent to check cross-task integration
- Result: INCONCLUSIVE -- reviewer found 0 issues, control waves also had 0 failures
- Lesson: shared API contract in worker prompts may prevent mismatches, making reviewer redundant
- Logged in PIPELINE_EXPERIMENTS.md

### Pipeline Observations
- Sonnet model used for task 7 (final verification) -- worked well, good cost optimization
- Lead coordination improved: clean DONE relay, wave transition reports, held verification for EXP-002
- Flaky test: topology_builder_test.exs fails in full suite but passes isolated (Phase 3 issue, not Phase 4)
- Total: ~20 min wall time, 7 workers, 204 tests

### Previous Milestones
- Phase 3: Topology & Entropy (7 tasks, 113 tests) -- commit 81f6054
- Phase 2: Gateway Core (5 tasks, 65 tests) -- commit ffff26d
- Phase 1: DecisionLog Schema (4 tasks, 36 tests) -- commit 2a10e77
- Mode C Pipeline: 7 FRDs -> 5 phases, 24 sections, 77 tasks, 225 subtasks
- Mode B Pipeline: 12 ADRs -> 6 FRDs -> 79 UCs

### Next Steps
- [ ] Phase 5 (next implementation phase)
- [ ] Fix flaky topology_builder_test.exs (test ordering issue)
- [ ] Code quality review of Phase 4 output
- [ ] Visual verification: browser test of HITL drilldown
- [ ] MONAD_LESSON_LOG.md evaluation for upstream skill amendments

## Architecture Reminders

- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> Ash.create + PubSub -> LiveView
- Zero warnings: `mix compile --warnings-as-errors`
- Module size limit: 200-300 lines max
- embed_templates pattern: .ex (logic) + .heex (templates)
