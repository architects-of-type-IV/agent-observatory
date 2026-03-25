# ICHOR IV - Handoff

## Current Status: EVENT/SIGNAL NAMESPACE SEPARATION COMPLETE (2026-03-25)

~153 .ex files. Build clean. Zero tests.

### Architecture (current)

```
Ash Action / GenServer / Worker
  -> Events.emit(Event.new("topic.string", key, data))
    -> Ingress.push (GenStage pipeline: Router -> SignalProcess -> Handler)
    -> PubSub broadcast on "events:all" + "events:{key}"
      -> Dashboard, SignalBuffer, Projectors match on %Event{topic: "..."}
```

### Event System (Events.*)
- `Events.emit/1` -- single public API, takes `%Event{}`
- `Events.subscribe_all/0` -- observe all events on "events:all"
- `Events.subscribe_key/1` -- observe events for a specific key
- `Events.Event` -- envelope struct: topic (string), key, data, metadata, occurred_at
- `Events.Ingress` -- GenStage producer (buffered demand tracking)
- `Events.StoredEvent` -- append-only PostgreSQL log
- `Events.EventStream` -- hook event ingestion (Claude Code webhooks)
- `Events.Registry` -- event topic catalog for /signals page sidebar (131 entries)

### Signal System (Signals.*)
- `Ichor.Signals` -- Ash Domain (Operations, Checkpoint resources)
- `Ichor.Signal` -- behaviour + `use` macro for signal modules
- `SignalProcess` -- GenServer per {signal_module, key}, accumulates events
- `Router` -- GenStage consumer, routes events to signal modules by topic
- `ActionHandler` -- dispatches signal activations to handlers
- `PipelineSupervisor` -- rest_for_one wrapping Ingress + Router
- 3 signal modules: ToolBudget, MessageProtocol, Entropy
- `Bus` -- message delivery authority
- `Operations` -- Ash Resource for agent messaging

### Hexagonal Layers
```
lib/ichor/
  factory/          # Ash domain: Pipeline, Project, PipelineTask + workers
  workshop/         # Ash domain: Agent, Team, Prompt + presets
  signals/          # Ash domain + GenStage signal pipeline
  settings/         # Ash domain: SettingsProject
  archon/           # Ash domain: system governor
  events/           # Ash domain: StoredEvent, Event, Ingress, EventStream, Registry
  fleet/            # OTP processes: AgentProcess, Supervisor, TeamSupervisor
  orchestration/    # Use cases: AgentLaunch, TeamLaunch, Registration, Cleanup
  infrastructure/   # I/O boundary: Tmux, webhooks, memories, host_registry
  projector/        # Event subscribers: AgentWatchdog, FleetLifecycle, etc.
```

### What Was Done This Session

1. **Catalog -> Registry**: Replaced 722-line Signals.Catalog with 250-line Events.Registry
2. **Namespace separation**: Moved event infra (Registry, Runtime, Message, Topics, EventStream) from Signals.* to Events.*
3. **Emit migration**: All 98 Signals.emit(:atom, data) calls -> Events.emit(Event.new("topic", key, data))
4. **Subscriber migration**: All 19 Signals.subscribe calls -> Events.subscribe_all/subscribe_key
5. **Renderer migration**: All 100+ %Message{name: :atom} patterns -> %Event{topic: "string"}
6. **Dead code removal**: Deleted Message, Runtime, Topics, Signals facade emit/subscribe

### Immediate Next: Remove legacy_name metadata

All Events still carry `%{legacy_name: :atom}` in metadata. This was the migration bridge.
Now that all renderers match on topic strings, legacy_name is dead. Remove it from all 98 emit sites.

### Open Items (from previous session, still pending)

HIGH:
- [ ] Fix `DashboardWorkshopHandlers` to use Workshop code_interface (not `Ash.destroy!` directly)
- [ ] Fix `WorkshopTypes` to use Workshop code_interface (not `Ash.destroy!` directly)
- [ ] Fix `ExportController` to use `Ichor.Events` domain code_interface

MEDIUM:
- [ ] X1: EventStream fleet mutations (calls Fleet directly, should emit event)
- [ ] X2: AgentWatchdog calls Factory.Board.update_task directly (should emit event)
- [ ] `MemoryStore` GenServer: evaluate if ETS public reads can bypass GenServer serialization

LOW:
- [ ] Frontend Wave 3: Migrate templates to use <.button>, <.input> from library
- [ ] Frontend Wave 4: Extract remaining page sections
- [ ] Fresh tests against event pipeline + Ash domain code_interfaces

### Build Status
- `mix compile --warnings-as-errors`: CLEAN
- `mix test`: 0 tests
- Credo strict: 0 issues (last checked)
