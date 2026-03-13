# Registry Redesign: Single Source of Truth

## Context

Two registries store overlapping agent data. Gateway.AgentRegistry (ETS GenServer) has rich display
data (model, current_tool, channels, last_event_at). Ichor.Registry (Elixir Registry) has thin
operational metadata (role, team, status). 40 files reference the ETS registry. The two drift apart
because they're written independently. The fleet sidebar is broken because LoadAgents can't decide
which to read from.

## Design

**Ichor.Registry is the single source of truth.** Gateway.AgentRegistry ETS is removed entirely.

### Registry metadata as the data store

Each `AgentProcess` registers via `{:agent, id}` with a rich metadata map:

```elixir
%{
  role: :worker,
  team: nil,
  status: :active,
  model: "opus",
  cwd: "/path/to/project",
  current_tool: "Bash",
  channels: %{tmux: "session:window", mailbox: "session_id"},
  os_pid: 12345,
  last_event_at: ~U[2026-03-13 20:00:00Z],
  short_name: "abc123",
  host: "local",
  parent_id: nil
}
```

Updated via `Registry.update_value/3` from within the AgentProcess.

### Signals as the nervous system

All state changes flow through Signals. Every consumer subscribes to the topics it cares about.

```
Event ingest -> Signals.emit(:hook_event, payload)
                    |
                    +---> AgentProcess (subscribed to own session_id signals)
                    |         |
                    |         v
                    |     Registry.update_value({:agent, id}, merge_fields)
                    |         |
                    |         v
                    |     Signals.emit(:fleet_changed, %{})
                    |
                    +---> Other subscribers (MemoriesBridge, CostAggregator, etc.)

Dashboard LiveView (subscribed to :fleet_changed)
    -> reads Registry on signal
    -> re-renders sidebar
```

**No polling. No recompute timers. No Agent.all!() on tick.**

The dashboard LiveView subscribes to `:fleet_changed` via Signals (Phoenix PubSub channels).
When it receives the signal, it reads the Registry and updates assigns. Fully reactive.

All frontend UI components subscribe to Signals topics. The dashboard is just another subscriber,
not a special consumer with its own polling loop.

No module reads events directly to build agent state. AgentProcess owns its own metadata.

### What moves where

| Current ETS function | New location |
|---------------------|-------------|
| `register_from_event` | AgentProcess handles signal, updates own Registry metadata |
| `register_spawned` | AgentProcess.init already does this -- enrich metadata |
| `update_tmux_channel` | AgentProcess handles `:tmux_channel_update` signal |
| `touch` | AgentProcess handles activity signal |
| `mark_ended` | AgentProcess.terminate (auto-deregisters from Registry) |
| `remove` | Process termination (automatic) |
| `list_all` | `AgentProcess.list_all` (Registry.select) |
| `get` | `AgentProcess.lookup` (Registry.lookup) |
| `resolve_channel` | Move to Router or Operator (reads Registry) |
| `build_lookup` | Move to DashboardState (reads Registry) |
| `dedup_by_status` | Unnecessary -- Registry is unique by key |
| `Sweep` | Unnecessary -- process death = auto-cleanup |
| `TeamSync` | Unnecessary -- team field set on AgentProcess.init |
| `IdentityMerge` | Unnecessary -- one process per agent, no merging |
| `EventHandler` | Logic moves into AgentProcess signal handlers |

### Pure utilities that survive

`AgentEntry.short_id/1`, `AgentEntry.uuid?/1`, `AgentEntry.role_from_string/1` are pure functions
with no ETS dependency. Move them to `Ichor.Fleet.AgentProcess` or a small helper module.

### LoadAgents becomes trivial

```elixir
def prepare(query, _opts, _context) do
  agents =
    AgentProcess.list_all()
    |> Enum.map(fn {id, meta} -> to_agent(id, meta) end)
    |> Enum.sort_by(fn a -> {status_sort(a.status), a.name} end)

  Simple.set_data(query, agents)
end
```

### Guarantee: no agent without a process

Every data path that currently writes to ETS must instead ensure an AgentProcess exists:
- Event ingest: `ensure_agent_process` before/after signal emission
- TmuxDiscovery: already creates AgentProcess (keep this)
- TeamSync: team membership updates go through signals to existing processes

If an event arrives for a session_id with no AgentProcess, create one first.

### Cluster readiness

Elixir Registry is node-local. For cluster distribution:
- `:pg` groups (already used by AgentProcess) provide cross-node discovery
- Registry metadata stays local to the node owning the process
- Cross-node reads go through `:pg` -> `GenServer.call` to the owning node

This is a future concern but the architecture supports it without redesign.

## Files to modify

### Delete
- `lib/ichor/gateway/agent_registry.ex` (GenServer + ETS)
- `lib/ichor/gateway/agent_registry/event_handler.ex`
- `lib/ichor/gateway/agent_registry/identity_merge.ex`
- `lib/ichor/gateway/agent_registry/team_sync.ex`
- `lib/ichor/gateway/agent_registry/sweep.ex`

### Keep (move pure functions)
- `lib/ichor/gateway/agent_registry/agent_entry.ex` -> move to Fleet or keep as utility

### Modify (replace ETS reads/writes with Registry)
- `lib/ichor/fleet/agent_process.ex` -- enrich metadata, add signal handlers
- `lib/ichor/fleet/preparations/load_agents.ex` -- already done
- `lib/ichor/gateway/router.ex` -- replace AgentRegistry calls
- `lib/ichor/gateway/tmux_discovery.ex` -- replace AgentRegistry calls
- `lib/ichor/agent_spawner.ex` -- replace register_spawned
- `lib/ichor/signals/catalog.ex` -- may need new signal types
- `lib/ichor/gateway/output_capture.ex` -- replace get()
- `lib/ichor/heartbeat.ex` -- remove purge_stale
- `lib/ichor/agent_monitor.ex` -- replace get()
- `lib/ichor/pane_monitor.ex` -- replace list_all
- `lib/ichor/nudge_escalator.ex` -- replace list_all
- `lib/ichor/gateway_supervisor.ex` -- remove AgentRegistry from supervision tree
- `lib/ichor_web/live/dashboard_state.ex` -- replace build_agent_lookup
- `lib/ichor_web/live/dashboard_*.ex` -- replace AgentRegistry calls (multiple handlers)
- `lib/ichor_web/controllers/debug_controller.ex` -- replace list_all
- `lib/ichor_web/components/fleet_helpers.ex` -- replace derive_role
- `lib/ichor/costs/cost_aggregator.ex` -- replace short_id calls
- `lib/ichor/event_buffer.ex` -- replace uuid?/short_id calls
- `lib/ichor/memories_bridge.ex` -- replace short_id calls

## Verification

1. `mix compile --warnings-as-errors` -- zero warnings
2. Server starts, fleet sidebar shows agents with names, models, tmux indicators
3. Start a new Claude session -- appears in sidebar within 5 seconds
4. Kill a tmux session -- agent disappears from sidebar
5. No references to `Gateway.AgentRegistry` remain in lib/ (except agent_entry utilities if kept)
