# Registry Redesign: Ichor.Registry as Single Source of Truth

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate Gateway.AgentRegistry ETS table. All agent state lives as metadata on Ichor.Registry entries. All consumers subscribe to Signals topics for updates.

**Architecture:** AgentProcess owns its Registry metadata. Events flow through Signals to AgentProcess, which updates its metadata via `Registry.update_value/3`, then emits `:fleet_changed`. Dashboard and all UI components subscribe to `:fleet_changed` via Signals. No polling.

**Tech Stack:** Elixir Registry, Phoenix PubSub (via Signals), GenServer

**Approach:** Incremental. Gateway.AgentRegistry stays alive until every consumer is migrated. Each task compiles clean. No big bang.

---

### Task 1: Enrich AgentProcess Registry Metadata

**Files:**
- Modify: `lib/ichor/fleet/agent_process.ex`

AgentProcess currently stores thin metadata in Ichor.Registry. Enrich it to carry everything the ETS table has.

**Step 1: Update init/1 to store rich metadata**

In `AgentProcess.init/1`, change `update_registry/2` call to include all fields:

```elixir
update_registry(id, %{
  role: role,
  team: team,
  status: :active,
  model: meta[:model],
  cwd: meta[:cwd],
  current_tool: nil,
  channels: %{
    tmux: tmux_target,
    mailbox: id,
    webhook: nil
  },
  os_pid: meta[:os_pid],
  last_event_at: DateTime.utc_now(),
  short_name: meta[:name] || id,
  host: meta[:host] || "local",
  parent_id: meta[:parent_id],
  backend_type: backend_type(state.backend),
  tmux_session: tmux_session,
  tmux_target: tmux_target,
  name: meta[:name] || id
})
```

**Step 2: Add public API for metadata updates**

Add to AgentProcess:

```elixir
@spec update_field(String.t(), atom(), term()) :: :ok
def update_field(agent_id, field, value) do
  GenServer.cast(via(agent_id), {:update_field, field, value})
end

@spec update_fields(String.t(), map()) :: :ok
def update_fields(agent_id, fields) when is_map(fields) do
  GenServer.cast(via(agent_id), {:update_fields, fields})
end
```

Handle in `handle_cast`:

```elixir
def handle_cast({:update_field, field, value}, state) do
  update_registry(state.id, %{field => value})
  {:noreply, state}
end

def handle_cast({:update_fields, fields}, state) do
  update_registry(state.id, fields)
  {:noreply, state}
end
```

**Step 3: Add signal subscription in init**

```elixir
# Subscribe to events about this agent
Ichor.Signals.subscribe(:agent_event, id)
```

**Step 4: Handle agent_event signals to update metadata**

```elixir
def handle_info({:signal, :agent_event, _topic, %{event: event}}, state) do
  fields = extract_fields_from_event(event)
  if fields != %{}, do: update_registry(state.id, fields)
  Ichor.Signals.emit(:fleet_changed, %{agent_id: state.id})
  {:noreply, state}
end
```

Add the extraction helper:

```elixir
defp extract_fields_from_event(event) do
  %{}
  |> maybe_put_model(event)
  |> maybe_put_cwd(event)
  |> maybe_put_tool(event)
  |> maybe_put_os_pid(event)
  |> Map.put(:last_event_at, event.inserted_at || DateTime.utc_now())
end

defp maybe_put_model(fields, event) do
  model = if event.hook_event_type == :SessionStart,
    do: (event.payload || %{})["model"] || event.model_name,
    else: event.model_name
  if model, do: Map.put(fields, :model, model), else: fields
end

defp maybe_put_cwd(fields, event) do
  if event.cwd, do: Map.put(fields, :cwd, event.cwd), else: fields
end

defp maybe_put_tool(fields, event) do
  case event.hook_event_type do
    :PreToolUse -> Map.put(fields, :current_tool, event.tool_name)
    type when type in [:PostToolUse, :PostToolUseFailure] -> Map.put(fields, :current_tool, nil)
    _ -> fields
  end
end

defp maybe_put_os_pid(fields, event) do
  if event.os_pid, do: Map.put(fields, :os_pid, event.os_pid), else: fields
end
```

**Step 5: Add fleet_changed signal to catalog**

In `lib/ichor/signals/catalog.ex`, add:

```elixir
fleet_changed: %{category: :fleet, keys: [:agent_id], doc: "Agent Registry metadata changed"},
```

**Step 6: Compile**

Run: `mix compile --warnings-as-errors`
Expected: clean

**Step 7: Commit**

```
feat(fleet): enrich AgentProcess registry metadata and add signal handlers
```

---

### Task 2: Migrate LoadAgents to Read from Ichor.Registry

**Files:**
- Modify: `lib/ichor/fleet/preparations/load_agents.ex` (already done, verify correct)

LoadAgents currently reads from `AgentRegistry.list_all()` (ETS). Change to `AgentProcess.list_all()` (Ichor.Registry).

**Step 1: Verify current LoadAgents reads from AgentProcess.list_all()**

The file was already rewritten. Verify it uses `AgentProcess.list_all()` and maps the metadata correctly. The metadata shape must match what Task 1 stores.

**Step 2: Compile**

Run: `mix compile --warnings-as-errors`

**Step 3: Commit (if changes needed)**

---

### Task 3: Migrate Router.ingest to Use Signals Instead of ETS Writes

**Files:**
- Modify: `lib/ichor/gateway/router.ex`

Router.ingest currently calls `AgentRegistry.register_from_event` and `AgentRegistry.mark_ended`. Replace with signal emissions that AgentProcess handles.

**Step 1: Remove ETS writes from ingest/1**

Replace:
```elixir
def ingest(event) do
  AgentRegistry.register_from_event(event)
  if event.hook_event_type in [:SessionEnd, "SessionEnd"] do
    AgentRegistry.mark_ended(event.session_id)
    terminate_agent_process(event.session_id)
  end
  handle_channel_events(event)
  agent = AgentRegistry.get(event.session_id)
  agent_name = if agent, do: agent.id, else: event.session_id
  Ichor.Signals.emit(:agent_event, agent_name, %{event: event})
  :ok
end
```

With:
```elixir
def ingest(event) do
  ensure_agent_process(event.session_id, event)

  if event.hook_event_type in [:SessionEnd, "SessionEnd"] do
    terminate_agent_process(event.session_id)
  end

  handle_channel_events(event)
  Ichor.Signals.emit(:agent_event, event.session_id, %{event: event})
  :ok
end
```

Add `ensure_agent_process` that creates an AgentProcess if one doesn't exist:

```elixir
defp ensure_agent_process(session_id, event) do
  unless AgentProcess.alive?(session_id) do
    opts = [
      id: session_id,
      role: :worker,
      metadata: %{
        cwd: event.cwd,
        model: event.model_name,
        os_pid: event.os_pid,
        name: session_id
      }
    ]

    case FleetSupervisor.spawn_agent(opts) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, _reason} -> :ok
    end
  end
end
```

**Step 2: Remove AgentRegistry alias from Router**

Remove `AgentRegistry` from the alias list. Keep other aliases.

**Step 3: Migrate Router.route/1 -- resolve_channel**

`route/1` calls `AgentRegistry.resolve_channel(pattern)`. This needs to read from Ichor.Registry instead. Move `resolve_channel` logic to Router itself using `AgentProcess.list_all()`:

```elixir
defp route(envelope) do
  resolve_recipients(envelope.channel)
end

defp resolve_recipients("agent:" <> name) do
  AgentProcess.list_all()
  |> Enum.filter(fn {id, meta} -> id == name || meta[:short_name] == name || meta[:name] == name end)
  |> Enum.map(fn {id, meta} -> %{id: id, session_id: id, channels: meta[:channels] || %{}} end)
end

defp resolve_recipients("session:" <> sid) do
  case AgentProcess.lookup(sid) do
    {_pid, meta} -> [%{id: sid, session_id: sid, channels: meta[:channels] || %{}}]
    nil -> []
  end
end

defp resolve_recipients("team:" <> team) do
  AgentProcess.list_all()
  |> Enum.filter(fn {_id, meta} -> meta[:team] == team end)
  |> Enum.map(fn {id, meta} -> %{id: id, session_id: id, channels: meta[:channels] || %{}} end)
end

defp resolve_recipients("role:" <> role) do
  role_atom = String.to_existing_atom(role)
  AgentProcess.list_all()
  |> Enum.filter(fn {_id, meta} -> meta[:role] == role_atom end)
  |> Enum.map(fn {id, meta} -> %{id: id, session_id: id, channels: meta[:channels] || %{}} end)
rescue
  ArgumentError -> []
end

defp resolve_recipients("fleet:" <> _) do
  AgentProcess.list_all()
  |> Enum.filter(fn {_id, meta} -> meta[:status] == :active end)
  |> Enum.map(fn {id, meta} -> %{id: id, session_id: id, channels: meta[:channels] || %{}} end)
end

defp resolve_recipients(_), do: []
```

**Step 4: Compile**

Run: `mix compile --warnings-as-errors`

**Step 5: Commit**

```
refactor(router): replace ETS writes with Signals + Ichor.Registry reads
```

---

### Task 4: Migrate TmuxDiscovery

**Files:**
- Modify: `lib/ichor/gateway/tmux_discovery.ex`

TmuxDiscovery calls `AgentRegistry.list_all_raw()`, `AgentRegistry.update_tmux_channel()`, `AgentRegistry.broadcast_update()`. Replace with Ichor.Registry reads and AgentProcess updates.

**Step 1: Replace poll/0**

```elixir
defp poll do
  tmux_sessions = Tmux.list_sessions()
  tmux_panes = Tmux.list_panes()

  ensure_beam_processes(tmux_sessions)
  enrich_tmux_channels(tmux_sessions, tmux_panes)
end
```

**Step 2: Replace enrich_tmux_channels to use AgentProcess**

```elixir
defp enrich_tmux_channels(tmux_sessions, tmux_panes) do
  for {id, meta} <- AgentProcess.list_all() do
    current_tmux = get_in(meta, [:channels, :tmux])

    if current_tmux && target_alive?(current_tmux, tmux_sessions, tmux_panes) do
      :ok
    else
      matched = find_target(id, meta, tmux_sessions, tmux_panes)

      if matched && matched != current_tmux do
        AgentProcess.update_fields(id, %{
          channels: Map.put(meta[:channels] || %{}, :tmux, matched),
          tmux_session: extract_session_name(matched),
          tmux_target: matched
        })
      end
    end
  end
end
```

**Step 3: Remove AgentRegistry alias**

**Step 4: Compile**

Run: `mix compile --warnings-as-errors`

**Step 5: Commit**

```
refactor(tmux-discovery): use Ichor.Registry instead of ETS
```

---

### Task 5: Migrate Remaining Consumers (Batch)

**Files to modify (each replaces AgentRegistry calls with AgentProcess equivalents):**

- `lib/ichor/agent_spawner.ex` -- replace `register_spawned` with metadata in AgentProcess.init
- `lib/ichor/agent_monitor.ex` -- replace `get()` with `AgentProcess.lookup()`
- `lib/ichor/pane_monitor.ex` -- replace `list_all` with `AgentProcess.list_all()`
- `lib/ichor/nudge_escalator.ex` -- replace `list_all` with `AgentProcess.list_all()`
- `lib/ichor/heartbeat.ex` -- remove `purge_stale` call (no sweep needed)
- `lib/ichor/gateway/output_capture.ex` -- replace `get()` with `AgentProcess.lookup()`
- `lib/ichor_web/live/dashboard_state.ex` -- replace `build_agent_lookup` with `AgentProcess.list_all()`
- `lib/ichor_web/live/dashboard_swarm_handlers.ex` -- replace AgentRegistry calls
- `lib/ichor_web/live/dashboard_slideout_handlers.ex` -- replace `get()`
- `lib/ichor_web/live/dashboard_session_control_handlers.ex` -- replace `get()` and `remove()`
- `lib/ichor_web/controllers/debug_controller.ex` -- replace `list_all`
- `lib/ichor_web/components/fleet_helpers.ex` -- replace `derive_role`
- `lib/ichor/fleet/preparations/load_teams.ex` -- replace `list_all` and `build_lookup`

For each file, the pattern is the same:
- `AgentRegistry.get(id)` -> `AgentProcess.lookup(id)` (returns `{pid, meta}` or `nil`, extract meta)
- `AgentRegistry.list_all()` -> `AgentProcess.list_all()` (returns `[{id, meta}]`)
- `AgentRegistry.remove(id)` -> `AgentProcess` termination handles cleanup automatically
- `AgentRegistry.derive_role(str)` -> inline or move to a helper module
- `AgentRegistry.dedup_by_status(pairs)` -> remove (Registry is unique)
- `AgentEntry.short_id(id)` / `AgentEntry.uuid?(id)` -> keep as utility, move import

**Step 1: Migrate each file, compile after each**

Run: `mix compile --warnings-as-errors` after each file

**Step 2: Commit per logical group**

```
refactor(consumers): migrate monitors and escalators to Ichor.Registry
refactor(dashboard): migrate dashboard handlers to Ichor.Registry
```

---

### Task 6: Move Pure Utilities, Delete ETS Registry

**Files:**
- Move: `lib/ichor/gateway/agent_registry/agent_entry.ex` -> `lib/ichor/fleet/agent_id.ex`
- Delete: `lib/ichor/gateway/agent_registry.ex`
- Delete: `lib/ichor/gateway/agent_registry/event_handler.ex`
- Delete: `lib/ichor/gateway/agent_registry/identity_merge.ex`
- Delete: `lib/ichor/gateway/agent_registry/team_sync.ex`
- Delete: `lib/ichor/gateway/agent_registry/sweep.ex`
- Modify: `lib/ichor/gateway_supervisor.ex` -- remove AgentRegistry from children

**Step 1: Create AgentId utility module**

Move `short_id/1`, `uuid?/1`, `role_from_string/1` to `Ichor.Fleet.AgentId`.

**Step 2: Update all imports**

Replace `alias Ichor.Gateway.AgentRegistry.AgentEntry` with `alias Ichor.Fleet.AgentId` across the codebase.

**Step 3: Delete ETS registry files**

Move to `tmp/trash/` per project rules.

**Step 4: Remove from GatewaySupervisor**

Remove `{Ichor.Gateway.AgentRegistry, []}` from children list. Change strategy from `:rest_for_one` to `:one_for_one` (no longer depends on registry ordering).

**Step 5: Update registry_changed signal**

In catalog, update or remove `registry_changed` signal (replaced by `fleet_changed`).

**Step 6: Compile**

Run: `mix compile --warnings-as-errors`
Expected: zero references to `Gateway.AgentRegistry` remain

**Step 7: Verify**

```bash
grep -r "AgentRegistry" lib/ --include="*.ex" | grep -v "AgentId"
```
Expected: zero matches

**Step 8: Commit**

```
refactor(registry): delete Gateway.AgentRegistry ETS, single source of truth is Ichor.Registry
```

---

### Task 7: Dashboard Subscribes to Signals (Reactive UI)

**Files:**
- Modify: `lib/ichor_web/live/dashboard_live.ex`
- Modify: `lib/ichor_web/live/dashboard_state.ex`
- Modify: `lib/ichor_web/live/dashboard_info_handlers.ex`

**Step 1: Subscribe to :fleet_changed in mount**

In `dashboard_live.ex` mount:
```elixir
Ichor.Signals.subscribe(:fleet_changed)
```

**Step 2: Handle fleet_changed signal**

In `dashboard_info_handlers.ex`, add handler:
```elixir
def handle_info({:signal, :fleet_changed, _, _payload}, socket) do
  {:noreply, DashboardState.recompute_fleet(socket)}
end
```

**Step 3: Add recompute_fleet to DashboardState**

Lightweight recompute that only refreshes agent data:
```elixir
def recompute_fleet(socket) do
  agent_index = build_agent_lookup(Ichor.Fleet.Agent.all!())
  assign(socket, :agent_index, agent_index)
end
```

**Step 4: Compile and verify**

Run: `mix compile --warnings-as-errors`

**Step 5: Commit**

```
feat(dashboard): subscribe to fleet_changed signal for reactive updates
```

---

## Verification

After all tasks complete:

1. `mix compile --warnings-as-errors` -- zero warnings
2. `grep -r "Gateway.AgentRegistry" lib/ --include="*.ex"` -- zero matches (except AgentId utility)
3. Server starts, fleet sidebar shows agents with names, models, tmux indicators
4. Start a new Claude session -- appears in sidebar within 5 seconds (signal-driven)
5. Kill a tmux session -- agent disappears (process death = Registry cleanup = fleet_changed signal)
6. No ETS table `:gateway_agent_registry` exists: `:ets.info(:gateway_agent_registry)` returns `:undefined`
