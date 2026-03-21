# ICHOR IV - Handoff

## Current Status: Wave 4 COMPLETE, Quality Pass Done (2026-03-21)

### Architecture Docs (authoritative)
`docs/architecture/decisions.md` (AD-1 through AD-8), `docs/plans/2026-03-21-architecture-audit.md` (all findings), `docs/plans/2026-03-21-vertical-slices.md`. See CLAUDE.md for full protocol.

### Wave Summary

| Wave | Score | Key Changes |
|------|-------|-------------|
| W1 (Foundation) | 7.5/10 | 7 prep tasks: Inbox, AgentWatchdog dedup, EventBridge, MemoriesClient, PromptProtocol, descriptions |
| W2 (Oban Migration) | 8/10 | 3 GenServers -> Oban (MesTick, ScheduledJob, WebhookDelivery) + reliability fixes |
| W3 (Structural) | 8/10 | X1 closed (EventStream decouple), X2 closed (TeamWatchdog signals+dispatchers), AD-6 partial, AD-8 closed |
| W4 (Large Structural) | Done | PipelineMonitor eliminated (623L -> pure query + 2 Oban cron), Ash resource domain moves (DB2) |
| Quality Pass | Done | Simplifier (dead code, banners, handlers) + Code reviewer (5 important findings fixed) |

### Closed Architecture Findings
- AD-8: Mandatory reactions via Oban, no volatile PubSub hops
- X1: EventStream -> Infrastructure one-way dependency
- X2: TeamWatchdog pure signal emitter, domain-local dispatchers
- O3: Cleanup actions as idempotent Oban workers
- P1: PipelineMonitor eliminated
- O4: Health check as Oban cron
- DB2: CronJob->Factory, HITL->SignalBus

### Open / Deferred
- AD-6 full: TeamSpec still has mode-specific build clauses (import violation gone, generic compile/2 deferred)
- AD-7: Value objects (RunRef/AgentId/SessionRef as Ash types, NOT OOP). 20+ files. Scoped.
- WX-tree: TREE.md update OVERDUE
- Low findings from review: AgentWatchdog memory leak (#6), reconciler cron gap (#7), stale @moduledoc (#8), TeamPrompts imports Factory (#9), signal category naming (#10)

### Oban Workers (current)
MesTick (cron 1m), ScheduledJob, WebhookDeliveryWorker, ArchiveRunWorker, ResetRunTasksWorker, DisbandTeamWorker, KillSessionWorker, HealthCheckWorker (cron 1m), ProjectDiscoveryWorker (cron 1m), OrphanSweepWorker (cron 5m)

### Commits This Session
```
495f31e  W2: Oban migration (3 GenServers)
(W2 fixes) W2 reliability fixes (8/10)
88e94a0  W3-2: AD-6 prompt strategy injection
da9fee2  W3-1: X1 EventStream decouple
c99d140  W3-4: AD-8 TeamWatchdog Oban cleanup
ae71b96  X1+AD-8 fix (ETS, direct insert)
ca72340  X2 fix (domain-local dispatchers)
19e5c80  W4-2: Ash resource domain moves
0d9fe83  W4-1: PipelineMonitor eliminated
c7c1091  Simplifier pass
(pending) Review fixes commit
```

### Build
- `mix compile --warnings-as-errors`: CLEAN
