# Observatory - Handoff

## Current Status: Overstory-Inspired Features (2026-03-08)

### Just Completed (5 features inspired by Overstory multi-agent orchestrator)

1. **Cost Dashboard** -- New `:costs` activity tab in fleet control view. Queries SQLite `token_usages` table via `CostAggregator`. Shows: total cost/input/output/cache summary cards, by-model breakdown with color-coded bars, per-agent cost bars with model labels. All data was already persisted -- this adds the UI.

2. **Progressive Nudging** (`NudgeEscalator`) -- GenServer that subscribes to heartbeat + events. 4-level escalation for stale agents:
   - Level 0: warn (log + PubSub broadcast)
   - Level 1: nudge (tmux message asking "are you still working?")
   - Level 2: escalate (HITL pause + operator alert)
   - Level 3: terminate (mark as zombie)
   Configurable thresholds via `config :observatory, NudgeEscalator`.

3. **Agent Spawning** (`AgentSpawner` + `Operator.spawn_agent/1`) -- Spawns Claude Code agents in tmux sessions via observatory socket. Pipeline: validate -> write overlay -> write hooks -> create tmux session -> launch claude. Dashboard events: `spawn_agent`, `stop_spawned_agent`.

4. **Quality Gate Enforcement** (`QualityGate`) -- GenServer that listens for `TaskCompleted` hook events. Looks up `done_when` from SwarmMonitor tasks. Runs the command. If it fails, sends a nudge to the agent via tmux/mailbox with the failure output. Broadcasts on `quality:gate` PubSub topic.

5. **Instruction Overlays** (`InstructionOverlay`) -- Generates per-agent CLAUDE.md files with: role definition (builder/scout/reviewer/lead), task assignment with acceptance criteria, file scope restrictions, quality gates, communication protocol (MCP inbox), completion protocol. Written to `.claude/OBSERVATORY_OVERLAY.md` in the agent's cwd.

### Architecture Changes
- **MonitorSupervisor**: Added `NudgeEscalator` and `QualityGate` GenServers
- **DashboardLive**: Subscribes to `agent:nudge`, `agent:spawned`, `quality:gate` PubSub topics
- **DashboardState**: Added `cost_data` assign, loaded via `CostAggregator.load_cost_data/0` in `recompute/1`
- **command_view.html.heex**: Added Costs tab (alongside Comms/Feed), fixed tab filtering logic

### New Files
| File | Purpose |
|------|---------|
| `lib/observatory/nudge_escalator.ex` | Progressive 4-level agent nudging |
| `lib/observatory/agent_spawner.ex` | Tmux-based agent spawn pipeline |
| `lib/observatory/instruction_overlay.ex` | Per-agent CLAUDE.md generation |
| `lib/observatory/quality_gate.ex` | TaskCompleted quality gate enforcement |
| `lib/observatory/costs/cost_aggregator.ex` | SQLite cost data aggregation |
| `lib/observatory_web/components/cost_components.ex` | Cost dashboard UI component |

### Modified Files
| File | Change |
|------|--------|
| `lib/observatory/monitor_supervisor.ex` | Added NudgeEscalator + QualityGate children |
| `lib/observatory/operator.ex` | Added spawn_agent/stop_agent delegates |
| `lib/observatory_web/live/dashboard_live.ex` | Spawn events, nudge/gate PubSub, 3 new topics |
| `lib/observatory_web/live/dashboard_state.ex` | cost_data assign + CostAggregator in recompute |
| `lib/observatory_web/live/dashboard_live.html.heex` | Pass cost_data to command_view |
| `lib/observatory_web/components/command_components/command_view.html.heex` | Costs tab, fixed tab filtering |

### Open Issues
1. **dashboard_live.ex at ~520 lines** -- Growing with spawn events. Still mostly one-line delegations.
2. **Task 8** -- Non-blocking event pipeline validation (load test). Low priority.
3. **Agent spawn UI** -- spawn_agent/stop_spawned_agent events wired but no form in the UI yet. Can be triggered via LiveView JS console or future spawn modal.
