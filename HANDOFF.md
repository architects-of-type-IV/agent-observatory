# ICHOR IV - Handoff

## Current Status: Wave 1 In Progress (2026-03-21)

### Session Accomplishments
1. Ash idiomacy audit (16 fixes) + code review (20 fixes) + dead code removal
2. Module decompositions: Runner, AgentWatchdog, EventStream, Spawn + PR #1 merge
3. Full architecture analysis: DDD, boundary violations, vertical slices, use cases
4. Codex sparring (3 rounds, 8.5/10) -> AD-8 reliability boundary
5. Comprehensive architecture docs: 9 files in docs/architecture/
6. tasks.jsonl created with 25-task wave plan
7. **W1-1 DONE**: Operator.Inbox module extracted

### Architecture Documentation
```
docs/architecture/
  INDEX.md                    -- master index + reading order
  decisions.md                -- AD-1 through AD-8
  target-file-structure.md    -- 146 target files
  supervision-tree.md         -- failure-domain supervisors
  memory-strategy.md          -- ETS/Stream rules, memory budgets
  workshop-domain.md          -- full CRUD plan
  factory-domain.md           -- project lifecycle, Oban workers
  signals-domain.md           -- EventStore, Bus, AD-8 reliability
  infrastructure.md           -- host layer, tmux, CommPolicy
```

### Wave 1 Status (Foundation)
- [x] W1-1: Extract Operator.Inbox module -- DONE
- [ ] W1-2: Extract Operator.Brain module
- [ ] W1-3: Collapse ichor_contracts into main app
- [ ] W1-4: Move Signals contracts into lib/ichor/signals/
- [ ] W1-5: Workshop: wire AgentSlot + CommRule as embedded resources
- [ ] W1-6: Introduce Ichor.Workshop.SpawnLink resource
- [ ] W1-7: Extract Ichor.Workshop.Spawn.Link as value object

### Key Files Changed (W1-1)
- `lib/ichor/operator/inbox.ex` -- NEW: canonical write path for ~/.claude/inbox/
- `lib/ichor/signals/agent_watchdog.ex` -- updated: uses Inbox.write instead of direct File.write
- `lib/ichor/archon/team_watchdog.ex` -- updated: dispatch :notify_operator uses Inbox.write

### Build
- `mix compile --warnings-as-errors`: CLEAN (W1-1 complete)
