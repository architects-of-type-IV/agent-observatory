# ICHOR IV - Handoff

## Current Status: Wave 2 COMPLETE, Wave 3 Ready (2026-03-21)

### Session Accomplishments (this session)
1. Wave 2: Oban migration -- 3 GenServers replaced with Oban workers + plain APIs
2. Codex review sent for Wave 2 (pending in codex-spar tmux session)
3. Stale worktree agent-a14dc367 completed (redundant, same work done in main)

### Wave 2 Status (Oban Migration) -- COMPLETE
- [x] W2-1: MesScheduler -> Oban cron (Factory.Workers.MesTick, * * * * *)
- [x] W2-2: CronScheduler -> Oban worker (Infrastructure.Workers.ScheduledJob)
- [x] W2-3: WebhookRouter -> Oban worker (Infrastructure.Workers.WebhookDeliveryWorker, max_attempts: 5, custom backoff)
- All three GenServers removed from supervisors
- Plain module APIs preserved (pause/resume, compute_signature, schedule_once, etc.)
- recover_jobs/0 called on application startup
- Oban config: 5 queues (webhooks: 10, quality_gate: 4, memories: 2, maintenance: 1, scheduled: 2)

### Wave 1 Status (Foundation) -- COMPLETE
- [x] W1-1 through W1-7: All done, Codex validated (7.5/10)

### Codex Wave 1 Review (7.5/10)
- AD-8: not yet fully closed (TeamWatchdog still PubSub-subscriber-driven cleanup -- Wave 3)
- Gaps carried forward: X1 (EventStream fleet), X2/O3 (TeamWatchdog), Problem 2/5

### Wave 3 Tasks (Structural) -- NEXT
- [ ] W3-1: EventStream decouple from fleet mutations (X1/Problem 2)
- [ ] W3-2: TeamSpec refactor -- strategy injection via compile/2 (AD-6)
- [ ] W3-3: Value objects for message/event payloads
- [ ] W3-4: TeamWatchdog -> mandatory Oban reaction (AD-8 closure)

### Architecture Documentation
```
docs/architecture/
  INDEX.md, decisions.md (AD-1 through AD-9), target-file-structure.md,
  supervision-tree.md, memory-strategy.md, workshop-domain.md,
  factory-domain.md, signals-domain.md, infrastructure.md
```

### Key Files Changed (Wave 2)
```
lib/ichor/factory/workers/mes_tick.ex          -- NEW: Oban cron worker
lib/ichor/factory/mes_scheduler.ex             -- REWRITTEN: plain module API
lib/ichor/infrastructure/workers/scheduled_job.ex       -- NEW: Oban worker
lib/ichor/infrastructure/cron_scheduler.ex              -- REWRITTEN: plain module API
lib/ichor/infrastructure/workers/webhook_delivery_worker.ex  -- NEW: Oban worker
lib/ichor/infrastructure/webhook_router.ex              -- REWRITTEN: plain module API
lib/ichor/infrastructure/webhook_adapter.ex             -- UPDATED: enqueue via Oban
lib/ichor/infrastructure/webhook_delivery.ex            -- UPDATED: get action added
lib/ichor/application.ex                                -- UPDATED: recover_jobs on startup
config/config.exs                                       -- Oban cron + queues
```

### Build
- `mix compile --warnings-as-errors`: CLEAN
