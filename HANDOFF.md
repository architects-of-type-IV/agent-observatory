# ICHOR IV - Handoff

## Current Status: Signals Migration COMPLETE (2026-03-11)

### Just Completed

**Migrated `Ichor.Signal` -> `Ichor.Signals` per signals.md convention**

- Namespace: `Ichor.Signal` -> `Ichor.Signals` across 42 consumer files
- Envelope: `Signal.Payload` -> `Signals.Message` with richer fields (kind, domain, correlation_id, causation_id, meta)
- New `Signals.Bus` -- sole PubSub transport interface
- New `Signals.Topics` -- centralized topic string builder
- `Signal.AshNotifier` -> `Signals.FromAsh` (Ash notification adapter)
- `Signal.Catalog` -> `Signals.Catalog` (preserved, compile-time validation)
- `Signal.Buffer` -> `Signals.Buffer`
- `Signal.Event` -> `Signals.Event`
- Old `lib/ichor/signal/` moved to `tmp/trash/`
- Config updated: `ash_domains` references `Ichor.Signals`

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN (225 files, 0 warnings)
- `mix credo --strict` -- 0 issues

### Architecture (per signals.md convention)
- **Bus**: only module that talks to Phoenix.PubSub
- **Topics**: only module that builds topic strings
- **Message**: single envelope struct for all signals (kind + domain + name + data)
- **Catalog**: compile-time signal registry with validation
- **FromAsh**: translates Ash notifications into Message envelope
- **Buffer**: subscribes to all categories, ETS ring buffer, re-broadcasts on stream:feed

### Runtime Notes
- Port 4005, `~/.ichor/tmux/obs.sock`
- Memories server on port 4000 (must be running for Archon memory tools)
