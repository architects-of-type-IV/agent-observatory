# ICHOR IV - Handoff

## Current Status: Wave 1 COMPLETE, Wave 2 Ready (2026-03-21)

### Session Accomplishments
1. Ash idiomacy audit (16 fixes) + code review (20 fixes) + dead code removal
2. Module decompositions: Runner, AgentWatchdog, EventStream, Spawn + PR #1 merge
3. Full architecture analysis: DDD, boundary violations, vertical slices, use cases
4. Codex sparring (3 rounds, 8.5/10) -> AD-8 reliability boundary
5. Comprehensive architecture docs: 9 files in docs/architecture/
6. tasks.jsonl created with 25-task wave plan
7. **Wave 1 COMPLETE**: All 7 tasks done, Codex validated (7.5/10)

### Architecture Documentation
```
docs/architecture/
  INDEX.md                    -- master index + reading order
  decisions.md                -- AD-1 through AD-9
  target-file-structure.md    -- 146 target files
  supervision-tree.md         -- failure-domain supervisors
  memory-strategy.md          -- ETS/Stream rules, memory budgets
  workshop-domain.md          -- full CRUD plan
  factory-domain.md           -- project lifecycle, Oban workers
  signals-domain.md           -- EventStore, Bus, AD-8 reliability
  infrastructure.md           -- host layer, tmux, CommPolicy
```

### Wave 1 Status (Foundation) -- COMPLETE
- [x] W1-1: Extract Operator.Inbox module (8c07f53)
- [x] W1-2: Remove AgentWatchdog duplicate functions (ec44a90)
- [x] W1-3: Fix EventBridge raw PubSub calls (00b3254)
- [x] W1-4: Move EventBridge to Mesh namespace (00b3254)
- [x] W1-5: Move MemoriesClient to Infrastructure (9de4fc8)
- [x] W1-6: Extract shared PromptProtocol (d1c561d)
- [x] W1-7: Add Ash action descriptions for Discovery (1aa8e5f)

### Codex Wave 1 Review (7.5/10)
- AD-1/AD-4: aligned (Inbox, MemoriesClient push side effects outward)
- AD-2: partial (EventBridge uses Signals facade now, but EventStream fleet mutations remain)
- AD-8: not yet (TeamWatchdog still PubSub-subscriber-driven cleanup -- Wave 2/3)
- PromptProtocol: S1 dedup done, AD-6 strategy injection deferred to Wave 3
- Gaps carried forward: X1 (EventStream fleet), X2/O3 (TeamWatchdog), Problem 2/5

### Wave 2 Tasks (Oban Migration) -- from architecture-audit.md
- [ ] W2-1: MesScheduler -> Oban cron worker (O1)
- [ ] W2-2: CronScheduler -> Oban cron entries (O2)
- [ ] W2-3: Webhook delivery -> Oban worker with retry (O5)

### Build
- `mix compile --force --warnings-as-errors`: CLEAN (272 files, 0 warnings)
