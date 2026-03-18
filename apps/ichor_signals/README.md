# ichor_signals

The ICHOR nervous system: signal catalog, PubSub transport, and the `Ichor.Signals.Domain`
Ash domain for persisted signal events.

## Ash Domains

**`Ichor.Signals.Domain`** -- owns one persisted resource.

| Resource | Description |
|---|---|
| `Ichor.Signals.Event` | A persisted signal event record (for audit and replay) |

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Signals.Catalog` | Compile-time declarative registry of every signal in the system. Source of truth for validation |
| `Ichor.Signals.Catalog.*Defs` | Category-scoped signal definitions (core, gateway/agent, genesis/dag, MES, team monitoring) |
| `Ichor.Signals.Bus` | Sole PubSub transport interface -- only module that calls `Phoenix.PubSub` directly |
| `Ichor.Signals.Runtime` | Host implementation of `Ichor.Signals.Behaviour`: validates via catalog, builds envelopes, broadcasts |
| `Ichor.Signals.Buffer` | Buffering layer for signal batching |
| `Ichor.Signals.FromAsh` | Bridges Ash action notifications into the signal system |

## Signal Categories

Defined in the catalog: `core`, `gateway`, `agent`, `team`, `mes`, `genesis`, `dag`.
Dynamic signals support a `scope_id` (e.g. per-session DAG deltas).

## Dependencies

- `ash` -- `Ichor.Signals.Domain` Ash domain
- `phoenix` -- `Phoenix.PubSub` transport
- `ichor_contracts` -- shared `Ichor.Signals.Behaviour` contract

## Architecture Role

`ichor_signals` is the lowest-level shared infrastructure used by all other apps.
The `Behaviour` contract in `ichor_contracts` allows sibling apps to emit signals
without depending on this app directly. The `Runtime` module in this app is the
concrete implementation configured via `config.exs`.
