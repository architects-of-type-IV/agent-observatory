# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents
- **Architect**: the user. **Archon**: AI floor manager. **Operator**: messaging relay.

## Signal-First Architecture
- ALL meaningful actions must emit a Signal. FromAsh notifier for 13 resources.
- `%Message{}` is the canonical envelope (from ichor_contracts).
- Buffer stores `{seq, %Message{}}` tuples in ETS ring buffer.
- LiveView uses `stream/stream_insert` with `at: 0, limit: 200` -- no list assigns.
- PubSub topic: `"signals:feed"` with shape `{:signal, seq, message}`.
- Per-category renderer components pattern match on `message.domain` then `message.name`.
- EntryFormatter/StreamEntry removed from live hot path. Keep for export/debug only.

## MessageRouter
- Single `send/1` API. Plain module (Iron Law). Replaces 10 paths.

## ichor_contracts
- Facade + behaviour + config dispatch for Ichor.Signals.
- Host configures `:signals_impl` -> `Ichor.Signals.Runtime`.

## Ash Domain Rules
- Domain is the ONLY public API. No direct resource access from handlers/tools.
- Genesis: 32 domain functions (Node + 9 sub-resources). All agent tools go through domain.
- Workshop: 11 domain functions. Persistence goes through domain.
- Mes: 10 domain functions. LiveView handlers + archon tools go through domain.
- Archon.Tools: real AshAi domain with 9 resources. Parent `Ichor.Archon` was empty placeholder (deleted).
- Use `set_attribute(arg(...))` not manual changeset fns.
- Use Ash.Type.Enum for finite value sets (5 HIGH extracted, 6 remaining).
- Use count aggregates instead of loading records to count.

## AgentWatchdog
- Merged from 4 GenServers: heartbeat + agent_monitor + nudge_escalator + pane_monitor.
- One `:beat` timer at 5s drives everything.
- 3 pure helpers: EventState, NudgePolicy, PaneParser.

## Dead Code Rules
- Zero-caller module = delete immediately.
- GenServer that only serializes ETS CRUD = demote to plain ETS + init/0.
- Three supervisors with independent children = merge into one_for_one.
- Single-function utility module = inline as private defp.
- Thin delegation wrapper = remove, rewire callers to real implementation.

## Performance Patterns
- LiveView Streams for real-time feeds (no list assigns at scale).
- Push filters into ETS via `:ets.select_delete`, `:ets.match_object`.
- Collapse multi-pass Enum chains to single `Enum.reduce`/`Enum.flat_map`.
- Use `:ets.info(:size)` not `length(:ets.tab2list())`.
- Stream over Enum on hot paths. Minimize intermediate allocations.
- No Task.async per signal -- worse than struct allocation (process + mailbox + ordering).

## Critical Constraints
- Module limit: 200L guide, SRP is the real rule. One module per file.
- Dispatch params first, accumulators first, unused params last.
- Ash Domain is canonical API. No direct resource access.
- No decorative banners. @doc and module structure for organization.
- Structs are contracts. Use @enforce_keys.
- credo --strict must be clean. Zero warnings.
- consolidate_protocols: false in dev (Ash Inspect warnings).

## User Preferences
- "Always go for pragmatism"
- "Take ownership" = fix ALL issues including pre-existing
- "Use codex actively as sparring partner"
- "Function names generic, focus on input/output shapes"
- "All messages through Signals first"
- "Structs are our contracts"
- "All needs to stream and flow, no data leakage"
- "Make sure edits done by ash-elixir-expert agents"
- "Offload git actions to background agents"
- "Coordinate whenever possible -- delegate, don't code directly"
- "Always consult codex for architecture decisions"
- "Backend should not handle formatting -- frontend LiveView components do per-event rendering"
