# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator.
- **Operator**: current thin messaging relay. Will eventually be replaced by Archon.

## Credo Cleanup Lessons (2026-03-11)
- `replace_all: true` corrupts alias declarations when old_string matches inside them. Example: replacing `Ichor.EventBuffer` with `EventBuffer` also transforms `alias Ichor.EventBuffer` into `alias EventBuffer` (invalid). Must fix manually after.
- `__MODULE__.function()` is valid for self-referencing Ash resources in `run` blocks (e.g., `__MODULE__.recent!()`)
- `Ash.DataLayer.Simple` is a common AliasUsage target in Ash preparations -- alias it.
- AliasOrder check requires alphabetical ordering of alias declarations.
- Framework modules (Phoenix.HTML.Form, Ash.Error.Unknown) also trigger AliasUsage.

## Signal Nervous System (CRITICAL)
- **Ichor.Signal** Ash Domain + API. `emit/2` (static), `emit/3` (dynamic/scoped)
- **Signal.Catalog**: compile-time, 45+ signals, 10 categories. `lookup!/1` raises on unknown.
- **Category-based routing**: PubSub `signal:{category}` + `signal:{category}:{name}`
- **Buffer**: subscribes to all categories, handles only `%Payload{}`
- **Dashboard**: single `Enum.each(Catalog.categories(), &Signal.subscribe/1)` covers all

## Agent Identity (CRITICAL)
- tmux session name IS canonical session_id
- Agent name is NEVER Path.basename(cwd)
- `AgentEntry.short_id/1` = single display abbreviation source
- "BEAM is god" -- every non-infrastructure tmux session has AgentProcess

## Dashboard Data Flow
- Mount seed: `EventBuffer.latest_per_session/0` (1 event/session)
- Never bulk-load ETS. Stream + minimal seed.
- Debounced recompute: 100ms coalesce

## DashboardLive Dispatch Pattern
- Handler modules expose `dispatch/3`, LiveView uses `when e in @events` guards
- Three recompute tiers: full (data), view-only (display), none (UI toggles)

## BEAM-Native Fleet
- AgentProcess GenServer: PID = identity, Delivery for transport
- TeamSupervisor DynamicSupervisor (one per team), FleetSupervisor (top-level)

## User Preferences (ENFORCED)
- "We dont filter. We fix implementation"
- "BEAM is god"
- "streaming non blocking memory efficient async data"
- Minimal JS. No emoji. Execute directly. No workers for credo.
