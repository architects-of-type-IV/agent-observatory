# ICHOR IV Architecture Guide

This document exists because we spent an entire session refactoring ~8,000 lines of accumulated mess. Every rule below was learned by fixing a violation of it. Follow these rules from the start and this refactor never happens again.

---

## The One Rule

**Ash Domains are the only entrypoints.** No LiveView, controller, agent, tool, or worker calls a resource directly. Everything goes through a domain code_interface `define`. If it's not in the code_interface, it doesn't exist to the outside world.

```elixir
# RIGHT: caller uses domain
Workshop.spawn_team(team_name)

# WRONG: caller reaches into resource
Ash.Changeset.for_update(team, :spawn_team, %{name: team_name}) |> Ash.update()
```

This is non-negotiable. It's how Ash enforces policies, how AshAi discovers tools, and how the system stays auditable.

---

## Hexagonal Layers

Dependencies point inward only. Never outward.

```
Adapters/Processes -> Orchestration -> Ash Domains
                                          ^
                                          |
                                    (never outward)
```

### Layer 1: Ash Domains (center)

`factory/`, `workshop/`, `signals/`, `settings/`, `archon/`, `events/`

Pure business state and actions. Ash Resources with PostgreSQL, ETS (Simple), embedded, or `:none` data layers. No GenServers, no I/O, no side effects in actions.

External APIs (tmux, HTTP clients, webhooks) are also Ash Resources with `data_layer: :none`. Generic actions wrap the I/O calls. This makes them discoverable, typed, and policy-guarded -- same as a database resource.

```elixir
# External API as Ash Resource
use Ash.Resource, domain: Ichor.Infrastructure, data_layer: :none

actions do
  action :list_sessions, {:array, :string} do
    run fn _input, _ctx -> {:ok, Tmux.list_sessions()} end
  end
end
```

### Layer 2: Orchestration (middle)

`orchestration/`

Use-case coordinators that call domain actions AND adapter functions. AgentLaunch, TeamLaunch, Registration, Cleanup. These are the only modules allowed to cross domain boundaries.

### Layer 3: Fleet + Infrastructure + Projectors (edge)

- `fleet/` -- OTP processes (AgentProcess, Supervisor, TeamSupervisor)
- `infrastructure/` -- I/O boundary (Tmux, webhooks, memories client, host_registry)
- `projector/` -- Signal subscribers that react to events

These depend on orchestration and domains. Domains never import from these.

### The test

```bash
# This should return ZERO hits:
grep -r "Fleet\.\|Orchestration\.\|Infrastructure\." lib/ichor/factory/ lib/ichor/workshop/ lib/ichor/settings/ --include="*.ex"
```

If a domain module imports from fleet/orchestration/infrastructure, the dependency arrow is wrong.

---

## Signals: Event vs Signal vs Handler

```
Event   = something happened     (domain fact, dot-delimited topic)
Signal  = enough happened        (accumulation threshold met)
Handler = now act                (Oban, HITL, notification, LLM)
```

### The pipeline

```
Ash Action -> %Event{} -> Ingress (GenStage) -> Router -> SignalProcess per {module, key} -> Handler
```

### Naming: big to small

```
agent.tool.budget.exhausted    -- good
agent.session.started          -- good
ToolBudgetExceededEvent        -- bad
new_event                      -- bad (framework noise)
fleet_changed                  -- bad (vague)
```

### Creating a signal module

```elixir
defmodule Ichor.Signals.Agent.ToolBudget do
  use Ichor.Signal

  @impl true
  def topics, do: ["agent.tool.completed"]

  @impl true
  def ready?(state, _trigger), do: state.count >= 500
end
```

The `use Ichor.Signal` macro provides defaults. Override only what differs.

### Reliability boundary (AD-8)

| Must happen | Mechanism | Why |
|-------------|-----------|-----|
| Cleanup, retry, reassignment | Oban job from Ash notifier | Durable. Survives crashes. |
| UI refresh, logging, metrics | PubSub signal from notifier | Fire-and-forget. Loss OK. |

Never route mandatory work through PubSub. The subscriber might be down.

---

## Ash Resource Rules

### Side effects go in notifiers, not after_action

```elixir
# WRONG: side effect in after_action (fires pre-commit, forces non-atomic)
change after_action(fn _, record, _ ->
  Signals.emit(:project_created, %{id: record.id})
  {:ok, record}
end)

# RIGHT: notifier fires post-commit
use Ash.Resource, simple_notifiers: [Ichor.Events.FromAsh]
```

### Prefer DSL builtins over fn blocks

```elixir
# WRONG: fn block for something DSL can do
change fn changeset, _ ->
  Ash.Changeset.change_attribute(changeset, :status, :active)
end

# RIGHT: DSL builtin
change set_attribute(:status, :active)
```

fn blocks force `require_atomic?(false)` and prevent atomic database operations.

### accept explicitly, never accept(:*)

```elixir
# WRONG: mass-assignment vulnerability
create :create do
  accept(:*)
end

# RIGHT: explicit fields
create :create do
  accept([:name, :email, :role])
end
```

### Embedded resources for structured data

```elixir
# WRONG: raw map
attribute :config, :map

# RIGHT: embedded resource with typed fields
attribute :location, Ichor.Settings.Location
```

### Aggregates over stored counts

```elixir
# WRONG: stored count alongside has_many
attribute :task_count, :integer
has_many :tasks, Task

# RIGHT: aggregate
aggregates do
  count :task_count, :tasks
end
```

---

## OTP Supervision

### Strategy selection

| Relationship | Strategy | Why |
|-------------|----------|-----|
| Children are independent | `one_for_one` | No cascade |
| Child B subscribes to child A by PID | `rest_for_one` | A restart cascades to B |
| Children share state that must be consistent | `one_for_all` | Full restart |

### Start order matters

If module B calls module A at runtime, A must start before B:

```elixir
children = [
  {Task.Supervisor, name: Ichor.TaskSupervisor},  # FIRST: others use it
  Ichor.RuntimeSupervisor,                          # SECOND: uses TaskSupervisor
  Ichor.Fleet.Supervisor,                           # THIRD: uses TaskSupervisor
]
```

### ETS tables die with their owner

No heir is set on any table. When a GenServer crashes, its ETS table is destroyed. Accept this for display buffers. For critical state, use PostgreSQL (StoredEvent, Checkpoint).

### restart: :transient for dynamic processes

AgentProcess, Runner, SignalProcess use `:transient` -- they stop normally (idle timeout, run complete) and should NOT restart. Abnormal crashes DO restart (OTP default for transient).

---

## Frontend Component Architecture

### Layered composition

```
Layer 0: ui/button.ex, ui/input.ex       -- base HTML tags
Layer 1: primitives/badge.ex, dot.ex     -- semantic primitives
Layer 2: agent/agent_actions.ex          -- domain components
Layer 3: page sections                   -- compose everything
```

### One file per component

Every component in its own file. No god component files. `IchorWeb.UI` library with `defdelegate` provides a single import.

### Use the library

```heex
<%-- RIGHT: library component --%>
<.button variant="primary" phx-click="save">Save</.button>

<%-- WRONG: raw CSS classes --%>
<button class="ichor-btn ichor-btn-primary" phx-click="save">Save</button>
```

---

## What NOT to do (learned the hard way)

### Don't create a junk drawer

`infrastructure/` had 34 files with 5 unrelated concerns. It should have been split from day one into fleet/, orchestration/, and infrastructure/ (I/O only).

**Rule: if a directory has more than 15 files, it's a junk drawer. Split it.**

### Don't build infrastructure for features that don't exist

The Mesh subsystem (CausalDAG, EventBridge, DecisionLog) was ~1,000 lines with zero consumers. The Plugin behaviour had zero implementors. HITL was -1,000 lines of complexity for a feature never used in practice.

**Rule: no code without a caller. If nothing calls it today, don't write it.**

### Don't duplicate logic across layers

Agent shutdown was implemented in 3 files with diverging HITL logic. The canonical path should be one function in orchestration/, called by everyone.

**Rule: if the same logic appears in 2+ places, extract it immediately. Don't wait.**

### Don't let signals become framework noise

`:new_event`, `:fleet_changed`, `:registry_changed` are implementation artifacts, not domain facts. Name signals as domain facts: `agent.session.started`, `pipeline.task.completed`.

**Rule: if the signal name doesn't make sense to a product person, rename it.**

### Don't skip the domain code_interface

Every `Ash.destroy!` or `Ash.create!` called from a LiveView is a boundary violation waiting to cause problems. It bypasses policies, breaks discoverability, and couples the UI to resource internals.

**Rule: add the `define` entry FIRST, then write the caller.**

### Don't use GenServers for code organization

A GenServer that holds no mutable state and exists only to "organize code" is overhead. Use plain modules. Only reach for GenServer when you need: mutable state across calls, concurrent execution, or fault isolation.

---

## File Naming Conventions

```
lib/ichor/
  {domain}/              # Ash domain directory
    {resource}.ex        # Ash Resource (snake_case of resource name)
    types/               # Ash.Type.Enum modules
    preparations/        # Ash.Resource.Preparation modules
    workers/             # Oban workers
  fleet/                 # OTP processes
  orchestration/         # Use-case coordinators
  infrastructure/        # I/O boundary adapters
  projector/             # Signal subscribers
  signals/
    agent/               # Signal modules by domain path
    pipeline/
```

Module name matches file path: `Ichor.Factory.Pipeline` -> `lib/ichor/factory/pipeline.ex`.

---

## Before Writing Code

1. Which domain owns this data? Put the resource there.
2. Is this a side effect? It goes in a notifier, not an action.
3. Does the DSL have a builtin for this? Use it instead of `fn`.
4. Who calls this? If nobody, don't write it.
5. Does the caller go through the domain code_interface? It must.
6. Is this a new directory? Keep it under 15 files.
7. Does this GenServer need to be a GenServer? Probably not.

Follow these and the codebase stays clean. Ignore them and we'll be here again in a month.
