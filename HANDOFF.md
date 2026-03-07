# Observatory - Handoff

## Current Status: Ash Domain Modeling Refactor IN PROGRESS (2026-03-07)

### Just Completed: Fleet + Activity Ash Domains + DashboardState

**Compile: zero warnings.**

Created two new Ash domains with 5 resources backed by `Ash.DataLayer.Simple` via shared preparations. Extracted `prepare_assigns/1` (215 lines) from `dashboard_live.ex` into `DashboardState.recompute/1`.

### New Ash Domains

| Domain | Resources | Data Source |
|--------|-----------|-------------|
| `Observatory.Fleet` | `Agent`, `Team` | EventBuffer ETS + TeamWatcher disk |
| `Observatory.Activity` | `Message`, `Task`, `Error` | EventBuffer ETS |

### Key Pattern: Preparation + set_data + filter DSL

```elixir
# Resource defines named actions with business intent
read :active do
  prepare {Fleet.Preparations.LoadAgents, []}
  filter expr(status != :ended)
end

# Shared preparation loads data from ETS
def prepare(query, _opts, _context) do
  agents = build_from_events(EventBuffer.list_events())
  Ash.DataLayer.Simple.set_data(query, agents)
end

# Usage: Fleet.Agent.active!() returns active agents
```

### Files Created (13)
| File | Lines | Purpose |
|------|-------|---------|
| `lib/observatory/fleet.ex` | 8 | Domain |
| `lib/observatory/fleet/agent.ex` | 50 | Resource: agents from events + tmux |
| `lib/observatory/fleet/team.ex` | 37 | Resource: teams from events + disk |
| `lib/observatory/fleet/preparations/load_agents.ex` | 265 | Builds agents from EventBuffer |
| `lib/observatory/fleet/preparations/load_teams.ex` | 205 | Builds teams from EventBuffer + TeamWatcher |
| `lib/observatory/activity.ex` | 9 | Domain |
| `lib/observatory/activity/message.ex` | 29 | Resource: SendMessage events |
| `lib/observatory/activity/task.ex` | 29 | Resource: TaskCreate/TaskUpdate events |
| `lib/observatory/activity/error.ex` | 52 | Resource: PostToolUseFailure events |
| `lib/observatory/activity/preparations/load_messages.ex` | 32 | Derives messages from events |
| `lib/observatory/activity/preparations/load_tasks.ex` | 70 | Derives tasks from events |
| `lib/observatory/activity/preparations/load_errors.ex` | 29 | Derives errors from events |
| `lib/observatory_web/live/dashboard_state.ex` | 270 | Replaces prepare_assigns |

### Files Modified
| File | Change |
|------|--------|
| `config/config.exs` | Added Fleet + Activity domains |
| `lib/observatory_web/live/dashboard_live.ex` | 1138 -> 920 lines. Removed prepare_assigns, uses DashboardState.recompute |

### Remaining Plan Steps
- [ ] Step 7: Move inline handlers to existing modules (tmux, selections, toggles, kill switch)
- [ ] Step 8: Retire absorbed helper modules (DashboardDataHelpers, DashboardTeamHelpers partial)
- [ ] Step 9: Final compile + smoke test

### Idiomatic Ash Code Interfaces
```elixir
Observatory.Fleet.Agent.active!()      # agents not ended
Observatory.Fleet.Agent.in_team!("x")  # agents in team x
Observatory.Fleet.Team.alive!()        # non-dead teams
Observatory.Activity.Message.recent!() # all messages
Observatory.Activity.Task.current!()   # all tasks
Observatory.Activity.Error.recent!()   # all errors
Observatory.Activity.Error.by_tool!()  # errors grouped by tool
```

## Architecture Reminders

- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- Zero warnings: `mix compile --warnings-as-errors`
- Module size limit: 200-300 lines max
- embed_templates pattern: .ex (logic) + .heex (templates)
- View modes: command (default), session_cluster, registry, scheduler, forensic, god_mode
