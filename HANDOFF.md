# ICHOR IV - Handoff

## Current Status: Credo COMPLETE (2026-03-11)

`mix credo --strict` -- 0 issues across 223 files
`mix compile --warnings-as-errors` -- CLEAN

### Next Task: Migrate Ichor.Signal -> Ichor.Signals per signals.md convention

The `signals.md` in project root defines the target architecture. Key changes:

1. **Namespace rename**: `Ichor.Signal` -> `Ichor.Signals` (all 45+ signal refs across ~30 files)
2. **Richer envelope**: `Payload{name, category, data, ts, source}` -> `Message{kind, topic, domain, resource, action, data, tenant_id, actor_id, correlation_id, causation_id, timestamp, meta}`
3. **Signal identity**: atom name (`emit(:agent_started, ...)`) -> tuple (`kind+domain+resource+action`)
4. **New modules**:
   - `Signals.Bus` -- sole PubSub interface (replaces direct Phoenix.PubSub in signal.ex)
   - `Signals.Topics` -- centralized topic string builder
   - `Signals.FromAsh` -- Ash notification -> Signals.Message adapter
   - `Signals.Message` -- replaces Payload
5. **API change**: `emit/2` -> `publish/1` with `new_message/7`
6. **Domain helpers**: optional per-domain signal modules (e.g., `Ichor.Fleet.Signals`)

### Current files to migrate:
- `lib/ichor/signal.ex` -> `lib/ichor/signals/signals.ex`
- `lib/ichor/signal/catalog.ex` -> absorbed into domain+resource+action identity
- `lib/ichor/signal/payload.ex` -> `lib/ichor/signals/message.ex`
- `lib/ichor/signal/buffer.ex` -> `lib/ichor/signals/buffer.ex` (update imports)
- `lib/ichor/signal/event.ex` -> `lib/ichor/signals/event.ex`
- `lib/ichor/signal/ash_notifier.ex` -> `lib/ichor/signals/from_ash.ex`
- NEW: `lib/ichor/signals/bus.ex`, `lib/ichor/signals/topics.ex`

### Subscribers to update (~30 files):
- All files that call `Ichor.Signal.emit/2` or `Ichor.Signal.emit/3`
- All files that call `Ichor.Signal.subscribe/1` or `Ichor.Signal.subscribe/2`
- All files that match `%Ichor.Signal.Payload{}`
- DashboardInfoHandlers, DashboardGatewayHandlers, DashboardLive (mount)

### Format-on-save Race Condition (IMPORTANT)
When editing `.ex` files, the format-on-save hook races with the Edit tool and reverts changes.
**Workaround**: use `cat > file << 'ELIXIR_EOF'` bash heredoc for full file writes.
For targeted edits: use `perl -i -0pe` for multiline pattern replacement.
