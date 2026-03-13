# ICHOR IV (formerly Observatory) - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, part of Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator.
- **Operator**: current thin messaging relay. Will eventually be replaced by Archon.

## Registry Architecture (2026-03-13, COMPLETE for process registries)
- User directive: **ONE registry for the entire ICHOR** -- `Ichor.Registry`
- **DONE**: Consolidated Fleet.ProcessRegistry + Fleet.TeamRegistry + Mes.Registry into `Ichor.Registry`
- Compound keys: `{:agent, id}`, `{:team, name}`, `{:run, id}`
- **Remaining**: Gateway.AgentRegistry (50 refs, ETS-based display cache) -- separate effort
- **Remaining**: `:pg` groups for cluster-wide discovery -- stays as-is (different purpose)

## MES Supervision Tree (2026-03-13, COMPLETE)
- **MES agents MUST be independent of RunProcess lifecycle** -- tmux is source of truth
- `Mes.AgentSupervisor` (DynamicSupervisor) owns MES agents, NOT Fleet.TeamSupervisor
- `MesAgentProcess` GenServer: monitors own tmux window (15s interval), self-terminates when dead
- RunProcess is spawner only -- terminate does NOT kill team or tmux
- **Signals.Catalog**: new signals must be added BEFORE any process can emit them. `lookup!/1` raises on unknown. `:mes_agent_stopped` and `:mes_agent_tmux_gone` now added.
- **Elixir Registry auto-cleanup**: when a process dies, its entry is automatically removed. Good for live state, bad for historical display. EventBuffer covers history.

## Agent Identity (CRITICAL)
- tmux session name IS canonical session_id
- Agent name is NEVER Path.basename(cwd)
- `AgentEntry.short_id/1` = single display abbreviation source
- "BEAM is god" -- every non-infrastructure tmux session has AgentProcess

## Credo Cleanup Lessons (2026-03-11)
- `replace_all: true` corrupts alias declarations when old_string matches inside them
- `__MODULE__.function()` is valid for self-referencing Ash resources in `run` blocks
- Framework modules (Phoenix.HTML.Form, Ash.Error.Unknown) also trigger AliasUsage
- Nesting: extract into `defp` helpers. `with` chains flatten nested `case`.

## Signals Convention (2026-03-11, COMPLETE)
- **Ichor.Signals** Ash Domain + API. `emit/2` (static), `emit/3` (dynamic/scoped)
- **Signals.Catalog**: compile-time, 45+ signals, 10 categories. `lookup!/1` raises on unknown.
- **Signals.Bus**: sole PubSub transport. **Signals.Topics**: centralized topic builder.

## Dashboard Data Flow
- Mount seed: `EventBuffer.latest_per_session/0` (1 event/session)
- Never bulk-load ETS. Stream + minimal seed.
- Debounced recompute: 100ms coalesce

## DashboardLive Dispatch Pattern
- Handler modules expose `dispatch/3`, LiveView uses `when e in @events` guards
- Three recompute tiers: full (data), view-only (display), none (UI toggles)

## User Preferences (ENFORCED)
- "We dont filter. We fix implementation"
- "BEAM is god"
- "1 registry only. For the entire ICHOR."
- "Needs to be perfect from the beginning. Can not be hard."
- Minimal JS. No emoji. Execute directly.
