# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents
- **Architect**: the user. **Archon**: AI floor manager. **Operator**: messaging relay.

## Signal-First Architecture
- ALL meaningful actions must emit a Signal. FromAsh notifier for Ash resources.
- `Ichor.Channels` shadow PubSub layer eliminated (was dead code).
- `events:stream` was a ghost topic -- 5 modules fixed to use Signals.subscribe.
- `%StreamEntry{}` is the common type for the signal livefeed.
- `EntryFormatter` has per-signal summarizers via pattern matching.

## MessageRouter
- Single `send/1` API. Plain module (Iron Law: no process).
- Replaces: Fleet.Comms, Tools.Messaging, Operator.send.
- All 14 callers go through MessageRouter directly.

## ichor_contracts
- Facade + behaviour + config dispatch for Ichor.Signals.
- Host configures `:signals_impl` -> `Ichor.Signals.Runtime`.
- Subsystems depend on ichor_contracts, never on host.

## Dead Code Removed (2026-03-19)
18 modules deleted: operator, channels, agent_spawner, 6 fleet wrappers, 4 gateway modules, 2 dag modules, mes/team_spawner, 2 web helper modules. 20+ dead functions removed. File count 410 -> 392.

## Performance Patterns
- Push filters into ETS via `:ets.select_delete`, `:ets.match_object`
- Collapse multi-pass Enum chains to single `Enum.reduce`/`Enum.flat_map`
- Use `:ets.info(:size)` not `length(:ets.tab2list())`
- Structs pass through `truncate_payload` unchanged (`%_{}` guard)

## Critical Constraints
- Module limit: 200L guide, SRP is the real rule. One module per file.
- Dispatch params first, accumulators first, unused params last.
- Ash Domain is canonical API. No direct resource access.
- No decorative banners. @doc and module structure for organization.
- @spec required on public API functions. Skip GenServer callbacks.
- credo --strict must be clean. Zero warnings.
- Structs are contracts. Use @enforce_keys.
- Stream over Enum on hot paths. Minimize intermediate allocations.

## User Preferences
- "Always go for pragmatism"
- "Take ownership" = fix ALL issues including pre-existing
- "Use codex actively as sparring partner"
- "Function names generic, focus on input/output shapes"
- "All messages through Signals first"
- "Structs are our contracts. We must be more strict."
- "All needs to stream and flow, no data leakage"
- "Make sure edits done by ash-elixir-expert agents"
- "Offload git actions to background agents"
