---
status: proposed
date: 2026-03-24
---

# ADR-026: Signal as Projector

## Context

The current signal system has a central `Catalog` that registers every signal name as an atom. Modules emit signals by name (`Signals.emit(:decision_log, data)`), and subscribers listen by category. The catalog owns the schema; the modules just call emit.

This creates several problems:

1. **The catalog is a central bottleneck.** Every new signal requires editing `catalog.ex`. The catalog knows every signal in the system but owns none of them.
2. **Signal data shapes are implicit.** A signal's data is a bare map. No struct, no type, no spec. Consumers pattern-match on map keys they hope exist.
3. **Formatting is orphaned.** When the MemoriesBridge needs to convert a signal to prose, it owns 40+ `narrate/2` clauses for data shapes it doesn't control. When a signal's data shape changes, the bridge breaks silently.
4. **No composition.** Signals are flat atoms. A higher-order signal (e.g., "enough gateway events accumulated to form a Memories episode") must be built outside the signal system.

## Decision

**A Signal is a Projector.** Each Signal module subscribes to PubSub topics, projects incoming events into a typed struct, and publishes the result. Signals compose -- a Signal can subscribe to other Signals.

### Core abstraction

```elixir
defmodule Ichor.Mesh.DecisionLog do
  use Ash.Resource, data_layer: :embedded
  use Ichor.Signal

  signal do
    subscribe :gateway
    publish :decision_log
  end

  # Ash resource: struct, attributes, types, actions
  attributes do
    attribute :meta, :map, public?: true
    attribute :identity, :map, public?: true
    attribute :cognition, :map, public?: true
    attribute :action, :map, public?: true
    attribute :state_delta, :map, public?: true
    attribute :control, :map, public?: true
  end

  # The resource owns its own formatting
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = log) do
    # ... extracts from its own fields
  end
end
```

The `use Ichor.Signal` macro:

- Injects a supervised GenServer (DynamicSupervisor + Registry)
- Subscribes to declared PubSub topics at init
- Delivers incoming messages to `handle_signal/2` (callback)
- The module projects raw PubSub events into its own struct
- Publishes the projected struct as a new signal

### Memories integration as composed Signals

The Memories bridge becomes Signal modules under `Ichor.Signals.Memories.*`. Each subscribes to domain Signals and projects them into `%Ichor.MemoriesBridge.Ingest{}` payloads.

```
Ichor.Signals.Memories.Gateway
  subscribes to: DecisionLog, DeadLetter, SchemaViolation
  projects into: %Ingest{type: :text, space: "project:ichor:gateway"}
  on threshold: Task.start(MemoriesClient, :ingest, [...])

Ichor.Signals.Memories.Fleet
  subscribes to: AgentStarted, AgentStopped, TeamCreated, ...
  projects into: %Ingest{type: :text, space: "project:ichor:fleet"}

Ichor.Signals.Memories.Mesh
  subscribes to: CausalDAG.Node
  projects into: %Ingest{type: :text, space: "project:ichor:mesh"}

Ichor.Signals.Memories.Agent
  subscribes to: MessageIntercepted, NudgeWarning, EntropyAlert
  projects into: %Ingest{type: :message, space: "project:ichor:agent"}
```

Each is small (~30-50 lines), owns its domain's formatting by calling `format/1` on the source Signals, and decides independently when it has enough content to emit an `%Ingest{}`.

### Catalog becomes derived

The catalog is no longer hand-maintained. At compile time, all modules that `use Ichor.Signal` register their published signal names. The catalog is the compiled set of all Signal modules.

### Supervision

```
DynamicSupervisor (Ichor.Signals.Supervisor)
  ├── Ichor.Mesh.DecisionLog        (GenServer, registered)
  ├── Ichor.Mesh.CausalDAG          (GenServer, registered)
  ├── Ichor.Signals.Memories.Gateway (GenServer, registered)
  ├── Ichor.Signals.Memories.Fleet   (GenServer, registered)
  ├── Ichor.Signals.Memories.Mesh    (GenServer, registered)
  ├── Ichor.Signals.Memories.Agent   (GenServer, registered)
  └── ...
```

Each GenServer crashes independently. Registry provides addressability. The DynamicSupervisor restarts crashed Signals. PubSub subscriptions are re-established on restart via init.

### Data flow

```
Raw PubSub event (from emit/2)
  → Signal GenServer (handle_info)
  → handle_signal/2 callback
  → projects into typed struct
  → publishes struct as new signal
  → downstream Signal GenServers receive it
  → ...
  → Memories.Gateway accumulates %DecisionLog{} structs
  → threshold met → builds %Ingest{} → Task.start(MemoriesClient.ingest)
```

### The %Ingest{} struct

Already implemented at `Ichor.MemoriesBridge.Ingest`. Matches the Memories `/api/episodes/ingest` API contract:

```elixir
%Ingest{
  content: String.t(),
  type: :text | :message | :json,
  source: :system,
  space: "project:ichor:gateway",
  extraction_instructions: "..."
}
```

## Consequences

### Positive

- **Signals own their data shape.** Struct, type, spec, format -- all on the module that knows the internals.
- **Catalog is derived, not maintained.** Adding a signal = adding a module. No central file to edit.
- **Composition.** Signals subscribe to Signals. The Memories projectors are just another layer of Signals.
- **Crash isolation.** Each Signal is a supervised GenServer. One crash doesn't take down the system.
- **Testable.** Each Signal module is a pure projection function wrapped in a GenServer. Test the projection without the process.

### Negative

- **Migration effort.** Every signal in the current catalog needs a module. ~50+ signal types across 11 categories.
- **Process count.** Each Signal is a GenServer. Hundreds of signals = hundreds of processes. Acceptable on BEAM, but more than today.
- **Learning curve.** "Signal as Projector" is a new concept for the team.

### Migration path

1. Build `use Ichor.Signal` macro
2. Implement `Ichor.Signals.Memories.*` modules against the new pattern (they subscribe to existing PubSub topics, so they work alongside the current system)
3. Migrate existing signals one category at a time from catalog to Signal modules
4. Remove catalog when empty

## Related

- ADR-014: Decision log envelope (DecisionLog struct)
- ADR-017: Causal DAG (CausalDAG.Node struct)
- ADR-023: BEAM-native agent processes (DynamicSupervisor + Registry pattern)
