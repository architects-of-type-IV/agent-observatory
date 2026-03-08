# ADR-023: BEAM-Native Agent Processes

> Status: PROPOSED | Date: 2026-03-08

## Context

Today, an "agent" in ICHOR IV is a row in an ETS table (`AgentRegistry`). It has no process, no mailbox, no lifecycle. Identity is inferred post-hoc from hook events and tmux session names, producing the dual-registration problem: the same agent appears under both a UUID (from hooks) and a short name (from `TeamWatcher` disk polling), and an expensive identity-merge step runs on every heartbeat to reconcile them.

Messages are delivered by writing JSON files to disk (`CommandQueue` at `~/.claude/inbox/{session_id}/`) and polling for pickup via MCP `check_inbox`. There is no way for an agent to receive a message without polling a filesystem directory.

This is the opposite of what the BEAM provides natively. Every Erlang process has a PID, a mailbox, selective receive, and monitor/link primitives. A GenServer adds call/cast/handle_info on top. These are the primitives ICHOR IV should be built from.

## Current State

| Concern | Mechanism | Problem |
|---------|-----------|---------|
| **Identity** | ETS row in `AgentRegistry` | No process; identity is a data record, not a living entity |
| **Registration** | `register_from_event/1` (hooks) + `TeamWatcher` (disk) | Dual registration, post-hoc merge required |
| **Mailbox** | `CommandQueue` (disk JSON) + `Mailbox` (ETS) | Polling-based; no push delivery to agents |
| **Lifecycle** | `:active` / `:ended` status flag in ETS | No supervisor; crash = silent disappearance |
| **Discovery** | `AgentRegistry.list_all/0` + manual dedup | Hand-rolled; no Registry module |

## Decision

Each agent that ICHOR IV manages becomes a `GenServer` process under a `DynamicSupervisor`. The process IS the agent. Its PID is the canonical identity. Its process mailbox is the delivery target.

### Agent Process (`Observatory.Fleet.AgentProcess`)

```elixir
defmodule Observatory.Fleet.AgentProcess do
  use GenServer

  defstruct [
    :id,              # stable identifier (e.g., "obs-builder-0042")
    :pid,             # self()
    :role,            # :worker | :lead | :coordinator | :archon
    :team,            # team name or nil for standalone
    :backend,         # %{type: :tmux, session: "...", host: "local"} | %{type: :ssh_tmux, ...}
    :capabilities,    # [:read, :write, :spawn, ...]
    :instructions,    # current system prompt / instruction overlay
    :status,          # :initializing | :active | :paused | :terminating
    :metadata         # arbitrary k/v (cwd, model, vendor, cost_accrued, etc.)
  ]

  # ── Public API ──

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: via(opts[:id]))
  def send_message(agent_id, message), do: GenServer.cast(via(agent_id), {:message, message})
  def get_state(agent_id), do: GenServer.call(via(agent_id), :get_state)
  def pause(agent_id), do: GenServer.call(via(agent_id), :pause)
  def resume(agent_id), do: GenServer.call(via(agent_id), :resume)
  def update_instructions(agent_id, instructions), do: GenServer.cast(via(agent_id), {:instructions, instructions})

  # ── Registry ──

  defp via(id), do: {:via, Registry, {Observatory.Fleet.AgentRegistry, id}}
end
```

Key properties:

1. **PID = identity.** No ETS row needed. `Registry.lookup/2` finds the process by name. No dual-registration, no merge step.

2. **Process mailbox = message delivery.** `GenServer.cast(via(id), {:message, msg})` delivers instantly. No disk writes, no polling. The `handle_cast` decides how to forward to the actual agent backend (tmux paste, SSH, webhook, etc.).

3. **Supervisor = lifecycle.** The process is supervised. If it crashes, the supervisor restarts it. If it terminates cleanly, `:DOWN` monitors fire. No heartbeat-based sweep needed to detect dead agents.

4. **Backend is pluggable.** The agent process doesn't know how to talk to tmux. It delegates to a backend module (`backend.type`) which implements the Channel behaviour. The process is the agent; the backend is the transport.

### Registration

Agent processes register via `Elixir.Registry` (not a hand-rolled ETS table):

```elixir
# In Application supervisor
{Registry, keys: :unique, name: Observatory.Fleet.AgentRegistry}

# Lookup
Registry.lookup(Observatory.Fleet.AgentRegistry, "obs-builder-0042")
# => [{pid, metadata}]
```

The current `Observatory.Gateway.AgentRegistry` GenServer with its ETS table, `build_lookup/1`, `dedup_by_status/1`, and sweep logic is replaced entirely. `Registry` handles uniqueness, lookup, and cleanup-on-crash natively.

### Spawn Flow

```
Architect clicks "Spawn Agent" in dashboard
  -> LiveView handle_event("spawn_agent", params, socket)
  -> Observatory.Fleet.spawn(params)
  -> DynamicSupervisor.start_child(Fleet.AgentSupervisor, {AgentProcess, params})
  -> AgentProcess.init/1:
       1. Register in Registry (automatic via `name: via(id)`)
       2. Start backend (tmux new-session, SSH connect, etc.)
       3. Deliver initial instructions
       4. Set status to :active
       5. Broadcast {:agent_spawned, id} on PubSub
```

No hooks needed for ICHOR-spawned agents. The process exists from the moment of spawn. External agents (those not spawned by ICHOR) still register via hook events, but `register_from_event/1` now starts an `AgentProcess` instead of inserting an ETS row.

### Message Delivery

```
Architect sends message via dashboard
  -> AgentProcess.send_message("obs-builder-0042", %{content: "..."})
  -> GenServer.cast(via("obs-builder-0042"), {:message, %{content: "..."}})
  -> handle_cast({:message, msg}, state):
       Channel.deliver(state.backend, msg)  # tmux paste, SSH, webhook, etc.
       broadcast {:message_sent, state.id, msg} on PubSub
```

One path. No Operator.send -> Gateway.Router.broadcast -> channel iteration. The agent process knows its own backend and delivers directly. The Gateway Router remains for pattern-based broadcast (`"team:frontend"`, `"fleet:all"`) which resolves targets via Registry, then casts to each.

## Consequences

- **Eliminates dual registration.** One process, one name, one lookup path.
- **Eliminates polling for messages.** Push delivery via GenServer.cast.
- **Eliminates heartbeat-based sweep.** Process monitors detect termination.
- **Eliminates identity merge.** No `build_lookup/1`, no `dedup_by_status/1`.
- **Preserves Channel behaviour.** Backend modules still implement `deliver/2` + `available?/1`. The agent process calls them; the Router no longer needs to.
- **Gateway Router simplifies.** Router resolves patterns to agent IDs, then casts to each. No more `deliver_to_agent/2` channel iteration -- that moves into the agent process.
- **Ash integration.** `Fleet.Agent` resource can read from Registry via a preparation (same pattern as today's `LoadAgents`, but calling `Registry.select/2` instead of ETS).
- **Migration is incremental.** AgentProcess can coexist with ETS registry during transition. New ICHOR-spawned agents use processes; legacy hook-registered agents use the old path until migrated.
