# ICHOR IV - Handoff

## Current Status: Full Code Review + Security Fixes (2026-03-21)

### Summary
Three audits in one session: (1) Ash idiomacy audit, (2) frontend dead code removal, (3) full code review with security/crash/reliability fixes. Build clean.

### What Was Done This Session

#### 1. Ash Idiomacy Audit (16 high findings)
- SyncPipelineProcess after_action -> notifier
- Pipeline task_count removed (computed from tasks)
- Bang calls -> non-bang with error handling
- allow_nil? added to tool arguments
- Helpers extracted from Agent resource -> AgentLookup
- Redundant code removed, error clauses added

#### 2. Frontend Dead Code Removal
- 8 dead files removed, dead delegates/functions cleaned

#### 3. Full Code Review (20 findings: 7 critical, 13 high)

**Security fixes (4):**
- C1: jq injection in jsonl_store.ex -> --arg flags
- C2: Shell injection in tmux/script.ex -> sanitize_name + single-quote
- C3: Path traversal in messaging_handlers -> cwd validation
- H1: CSV injection in export_controller -> csv_escape helper

**Backend crash fixes (6):**
- C4: Bus.send bare match -> case with error handling
- C5: AgentWatchdog unpause -> try/catch for dead HITLRelay
- C6: Signals.emit dynamic check -> ArgumentError instead of MatchError
- H3: Runner handle_cast -> wrapped apply result
- H4: Board.ex String.to_integer -> Integer.parse with filter
- H5: Spawn.ex bang -> non-bang with error tuple

**Frontend crash fixes (5):**
- C7: EventController bare match -> try/rescue
- H2: LiveView stream_insert guard -> check stream exists
- H8: MES handler File.write! -> File.write with error handling
- H9: Team broadcast missing error clause -> added
- H11: DashboardState silent rescue -> added logging

**Reliability fixes (5):**
- H6: AgentProcess unbounded unread -> only buffer without backend
- H7: Blocking tmux in app start -> async Task.start
- H10: PubSub subscription leak -> documented idempotent behavior
- H12: LifecycleSupervisor side effects -> guard on {:ok, _}
- H13: EventStream tombstone signals -> guard emission

### Build
- `mix compile`: 0 new warnings, 0 errors
- Migration `20260321024007` applied (task_count removed)

### Next
- Commit all changes
- Design & boundary improvements (user requested)
- ichor_contracts cleanup
- Oban worker migration
