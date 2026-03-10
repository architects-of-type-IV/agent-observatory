# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator. Will be a real AI agent with tools + memory + LLM.
- **Operator**: current thin messaging relay (Architect -> agents). Will eventually be replaced by Archon.
- ADR-001: vendor-agnostic fleet control, ADR-002: ICHOR IV identity

## Signal Nervous System (2026-03-10, CRITICAL)
- **Ichor.Signal** is an Ash Domain + convenience API. `emit/2` (static), `emit/3` (dynamic/scoped)
- **Signal.Catalog**: compile-time definitions, 45+ signals, 10 categories. `lookup!/1` raises on unknown.
- **Signal.Payload**: `%Payload{name, category, data, ts, source}` -- the ONLY broadcast struct subscribers match
- **Category-based routing**: PubSub topics `signal:{category}` + `signal:{category}:{name}`
- **Dynamic signals**: `dynamic: true` in catalog, `emit/3` with scope_id for per-agent/session topics
- **Telemetry tap**: every emit calls `:telemetry.execute([:ichor, :signal, name], %{count: 1}, ...)`
- **Zero scattered PubSub**: all inter-module broadcasts go through Signal.emit. Only exceptions: signal.ex internals (4), buffer.ex stream:feed (1), channels.ex transport (4)
- **Buffer is Signal-only**: subscribes to all categories, handles only `%Payload{}`, ~80 lines
- **Dashboard subscription**: single `Enum.each(Catalog.categories(), &Signal.subscribe/1)` covers all signals
- **Catch-all safety**: `def dispatch(%Payload{}, socket), do: {:noreply, socket}` -- new signals never crash dashboard
- **Debounced recompute**: 100ms coalesce via Process.send_after in DashboardInfoHandlers

## Agent Identity Architecture (2026-03-10, CRITICAL)
- **tmux session name IS the canonical session_id** -- EventBuffer.resolve_session_id uses it unconditionally
- **Agent name is NEVER Path.basename(cwd)** -- project dir goes in `:project` field
- **`AgentEntry.short_id/1`** = single source for display abbreviation. Binary pattern match uuid?/1.
- **"We dont filter. We fix implementation"** -- only "obs" + numeric sessions are infrastructure
- **"BEAM is god"** -- TmuxDiscovery enforces: every non-infrastructure tmux session has AgentProcess
- **Ghost detection**: no events + no tmux + status :ended/:unknown. Uses :status field.
- **Shutdown preserves events**: tombstone_session not remove_session. Agent stays visible as ended.
- **Session aliases**: EventBuffer ETS caches UUID->tmux_session. Late events resolve via alias.
- **Tombstones**: 30s ETS marker blocks events for dead sessions.
- **os_pid**: OS PID of Claude process, captured by hook PID tree walk.

## Dashboard Data Flow (2026-03-10, CRITICAL)
- **Mount seed**: `EventBuffer.latest_per_session/0` seeds `assigns.events` with 1 event per session
- **Memory rule**: never bulk-load ETS into LiveView assigns. Stream + minimal seed.
- **Debounced recompute**: rapid-fire signals coalesced via 100ms timer, single recompute cycle

## DashboardLive Dispatch Pattern
- Each handler module exposes `dispatch/3`, LiveView uses `when e in @events` guards
- Three recompute tiers: full (data), view-only (display), none (UI toggles)
- `DashboardInfoHandlers.dispatch/2` handles ALL handle_info messages via `%Payload{}` matching

## Archon Architecture (2026-03-10)
- `Archon.Tools` subdomain (17 tools, 7 resources), `Archon.Chat` (LangChain + AshAi)
- Fleet tools in-process; Memory tools HTTP localhost:4000 via MemoriesClient
- **No autonomous triggers yet** -- tools without triggers = chatbot. Watchdog planned (Option C).

## GC Architecture (2026-03-10, CRITICAL)
- **Observable liveness > hooks**: sweep checks `kill -0` (PID) + tmux session list
- **Safe-by-default**: `live_tmux_sessions/0` returns `{:ok, MapSet} | :error`
- **Two-layer**: BEAM-level (Sweep, 1min) + display-layer (LoadAgents.filter_stale)

## BEAM-Native Fleet Architecture
- **AgentProcess** GenServer: PID = identity, Delivery module for backend transport
- **TeamSupervisor** DynamicSupervisor (one per team), **FleetSupervisor** (top-level)
- **PubSub topics**: "fleet:lifecycle", "messages:stream" (transport, not signals)

## Subagent Architecture (2026-03-09)
- **Subagents are metadata on parents**, not separate Fleet.Agent entries
- **Data source**: PreToolUse "Agent"/"Task" events. **Pairing**: by `tool_use_id`.

## User Preferences (ENFORCED)
- **"We dont filter. We fix implementation so filtering out is not needed."**
- **"BEAM is god"** -- every agent tmux session must have a BEAM AgentProcess
- **"streaming non blocking memory efficient async data"** -- never bulk-load
- Minimal JavaScript. BEAM-native vision. No emoji. Execute directly.
- Build modular. DRY CSS. Ash-first. `.env` for secrets.
