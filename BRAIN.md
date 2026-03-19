# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents
- **Architect**: the user. **Archon**: AI floor manager. **Operator**: messaging relay.

## Signal-First Architecture
- ALL meaningful actions must emit a Signal. FromAsh notifier for 13 resources.
- `%StreamEntry{}` is the common type. `EntryFormatter` has per-signal summarizers.
- `events:stream` ghost topic fixed -- 5 modules switched to Signals.subscribe.

## MessageRouter
- Single `send/1` API. Plain module (Iron Law). Replaces 10 paths.

## ichor_contracts
- Facade + behaviour + config dispatch for Ichor.Signals.
- Host configures `:signals_impl` -> `Ichor.Signals.Runtime`.

## Ash Domain Rules
- Domain is the ONLY public API. No direct resource access from handlers/tools.
- Genesis domain currently only wraps Node -- needs extension for all 9 sub-resources.
- Use `set_attribute(arg(...))` not manual changeset fns.
- Use Ash.Type.Enum for finite value sets (11 candidates identified).
- Use count aggregates instead of loading records to count.
- Refer to `mix usage_rules.search_docs` for canonical Ash patterns.

## Dead Code Rules
- Zero-caller module = delete immediately.
- GenServer that only serializes ETS CRUD = demote to plain ETS + init/0.
- Three supervisors with independent children = merge into one_for_one.
- Single-function utility module = inline as private defp.

## Performance Patterns
- Push filters into ETS via `:ets.select_delete`, `:ets.match_object`
- Collapse multi-pass Enum chains to single `Enum.reduce`/`Enum.flat_map`
- Use `:ets.info(:size)` not `length(:ets.tab2list())`
- Structs pass through `truncate_payload` unchanged (`%_{}` guard)
- Stream over Enum on hot paths. Minimize intermediate allocations.

## Critical Constraints
- Module limit: 200L guide, SRP is the real rule. One module per file.
- Dispatch params first, accumulators first, unused params last.
- Ash Domain is canonical API. No direct resource access.
- No decorative banners. @doc and module structure for organization.
- Structs are contracts. Use @enforce_keys.
- credo --strict must be clean. Zero warnings.

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
- "Do all validations/calculations follow mix usage_rules.search_docs?"
