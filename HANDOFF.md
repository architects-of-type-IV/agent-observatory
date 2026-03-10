# ICHOR IV - Handoff

## Current Status: Signal Nervous System Migration COMPLETE (2026-03-10)

### Just Completed

**Signal Nervous System -- full PubSub migration to Ichor.Signal**
- Migrated ALL 52+ scattered `Phoenix.PubSub.broadcast` calls across 27+ files to `Ichor.Signal.emit`
- ALL subscribers rewritten from ad-hoc tuple matching to `%Ichor.Signal.Payload{}` pattern matching
- `Signal.Catalog`: 45+ signals across 10 categories (fleet, system, events, gateway, agent, hitl, mesh, team, monitoring, messages)
- `Signal.Buffer` fully rewritten: Signal-only (subscribes to categories, handles only Payload structs), ~80 lines (was ~205)
- `DashboardInfoHandlers` fully rewritten: all dispatch clauses match `%Payload{name: ..., data: ...}`
- `DashboardGatewayHandlers` fully rewritten: `handle_gateway_info` matches `%Payload{}`
- Dashboard mount subscribes to ALL Signal categories: `Enum.each(Catalog.categories(), &Signal.subscribe/1)`
- `@pubsub_topics` reduced to just `~w(agent:operator)` (transport only)
- Debounced recompute: 100ms coalesce via `schedule_recompute/1`

**Remaining intentional PubSub.broadcast (9 calls, all correct):**
- `signal.ex` (4): internal Signal system PubSub layer -- the implementation underneath Signal.emit
- `signal/buffer.ex` (1): re-broadcasts to "stream:feed" for /signals page
- `channels.ex` (4): messaging transport (publish_to_agent, publish_to_team, etc.) -- NOT signals

### Build Status
`mix compile --warnings-as-errors --force` -- CLEAN (223 files, 0 warnings)

### Pending / Next
- **Dialyzer**: PLT built, results not yet checked
- **Credo**: 1 warning (length/1 vs empty list), 4 `[F]` issues (nesting/complexity), ~244 suggestions
- **Archon.Watchdog** -- tiered rules + LLM escalation (Option C)
- **Archon CSS tokenization**: archon-* classes still use hardcoded rgba()
- Wire os_pid into liveness detection (kill -0)

### Key Architecture Decisions
- **Signal is the nervous system**: all inter-module communication flows through typed `Ichor.Signal.Payload` structs
- **Category-based routing**: broadcasts to `signal:{category}` AND `signal:{category}:{name}` topics
- **Dynamic signals**: `emit/3` with scope_id for per-agent/per-session scoping (terminal_output, gate_open, etc.)
- **Telemetry tap**: every emit fires `:telemetry.execute([:ichor, :signal, name], ...)`
- **Backwards-compatible catch-all**: `def dispatch(%Payload{}, socket), do: {:noreply, socket}` -- new signals won't crash dashboard

### Runtime Notes
- Port 4005, `~/.ichor/tmux/obs.sock`
- Memories server on port 4000 (must be running for Archon memory tools)
