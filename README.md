# signals

Stateful accumulators that correlate unrelated events into conclusions.

No required dependencies.

> Every event in the system is a topic. Topics are the atoms. Signals are the
> molecules.

## The idea

An event on its own says almost nothing. `agent.tool.invoked` is not a problem;
the *same* tool invoked three times running is. `agent.session.started` is not a
problem; started with nothing since is. Three agents crashing is a systemic
fault; one crashing is Tuesday.

No event carries that meaning, because the meaning is in the *relationship
between several of them*.

A **Signal** is where a few unrelated events become related. It picks a set of
topics, keeps whatever state its own logic needs, and the moment that state
means something, emits a signal event saying so.

```
Event source → topic → Signal (accumulates) → signal.<name> → subscriber
```

Each arrow is a clean boundary. The Signal is in the middle: it consumes topics,
it emits topics, it is neither.

## A signal is not a topic

**You cannot subscribe to a signal.** A signal listens to topics and emits to
one. Consumers subscribe to `signal.<name>`, not to the signal.

That one rule is what makes meta-signals fall out for free. A signal declaring
`topics: ["signal.*"]` consumes other signals' conclusions as its own input —
no special mechanism, because an emission is an ordinary event.

## Install

```elixir
def deps do
  [{:signals, path: "../signals"}]
end
```

```elixir
children = [Signals.Supervisor]

config :signals,
  signals: [MyApp.Signals.LoopDetected, MyApp.Signals.Watchdog],
  store: Signals.Store.ETS,
  sink: Signals.Sink.Local
```

## Writing one

Most signals are three or four callbacks — the ones carrying their actual
reasoning. `use Signals.Signal` defaults the rest.

```elixir
defmodule MyApp.Signals.LoopDetected do
  use Signals.Signal

  @impl true
  def name, do: "loop_detected"

  @impl true
  def topics, do: ["agent.tool.invoked"]

  @impl true
  def init(key), do: %{key: key, recent: []}

  @impl true
  def handle_event(event, state),
    do: %{state | recent: Enum.take([event.data["tool"] | state.recent], 5)}

  @impl true
  def ready?(%{recent: [t, t, t | _]}, _trigger), do: true
  def ready?(_state, _trigger), do: false

  @impl true
  def build_emission(%{key: key, recent: [tool | _]}),
    do: %{agent_id: key, tool: tool}

  @impl true
  def reset(state), do: %{state | recent: []}
end
```

The three parts are deliberately separate:

| Part | Callback | Question |
|---|---|---|
| Selection | `topics/0` | Which unrelated events might mean something together? |
| Accumulation | `handle_event/2` | What do I need to remember? |
| Conclusion | `ready?/2`, `build_emission/1` | Has it become true, and what do I say? |

`topics/0` is the interesting one. It isn't configuration — it's the *claim*
about which unrelated facts are worth considering side by side. Because it's
declarative data, the subscription graph is inspectable without running
anything: `Signals.subscriptions/0` is the cross-influence map.

## Three kinds of correlation

The bundled examples exist to show the three shapes, and they're the test corpus.

**By sequence** — `LoopDetected`. The same tool three times running. The
difference between fine and broken lives nowhere in either event, only in their
adjacency. The agent is busy, responsive, and making no progress; every liveness
check reads it as healthy.

**By absence** — `AgentSilent`. Concluding that *nothing* happened needs a
timer, because no event will ever arrive to say so. `interval/0` is what makes
this possible, and `ready?(state, :timer)` is where it gets decided. Note it
latches: a persistently silent agent alerts once, not every tick.

**Across subjects** — `CrashCascade`. Three *different* subjects failing.
Per-subject partitioning could never see more than one, so the signal declares
`partition_key(_) = "global"` and accumulates across all of them.

That last one matters more than it looks. **How a signal partitions is the
signal's business, not the emitter's.** An event is right to carry its own
subject; a downstream signal wanting to count across subjects says so itself.
Otherwise every emitter has to know every consumer.

## Meta-signals

`CompoundAlert` watches `signal.*` — other signals' conclusions. Several
*distinct kinds* of problem at once is a different claim than any one of them.

```
### subscription graph
  loop_detected    watches ["agent.tool.invoked"]
  crash_cascade    watches ["agent.crashed"]
  compound_alert   watches ["signal.*"]   [meta]

### what got concluded
  signal.loop_detected     subject="agent-1" depth=1
      %{tool: "Read", repeats: 3, agent_id: "agent-1"}
  signal.crash_cascade     subject="global"   depth=1
      %{count: 3, agents: ["agent-3", "agent-2", "agent-1"]}
  signal.compound_alert    subject="global"   depth=2
      %{signals: ["crash_cascade", "loop_detected"]}
```

Emissions carry a causal `depth`, capped by `:max_emission_depth`. Two
meta-signals watching each other would otherwise loop forever — and a loop of
signals looks exactly like healthy throughput from outside.

## Events are CloudEvents

`Signals.Event` uses [CloudEvents v1.0.2](https://cloudevents.io) attribute
names rather than a private envelope, so events cross a process, a node, or a
broker without translation.

| Attribute | Holds |
|---|---|
| `type` | The topic, dot-delimited big-to-small: `agent.tool.completed` |
| `source` | What produced it: `backend`, `frontend`, `temporal`, or a URI |
| `subject` | Default partition key — what the event is about |
| `id`, `time`, `data` | As specified |

`to_cloudevent/1` and `from_cloudevent/1` round-trip, with extensions flattened
to top level as the spec requires. `position` is an extension.

CloudEvents specifies the atom and stops there — it has no notion of
accumulation, threshold, or emission. That gap is exactly what this library is.

## Durability

An accumulator holds a *partial* conclusion — three of the five crashes that
make a cascade. Losing it on restart doesn't lose an event; it loses the
reasoning so far, silently. A watchdog that resets its clock every deploy never
fires. So the partial conclusion is persisted and restored on start.

`Signals.Store.ETS` is the development default and is **not** durable. Back it
with a database anywhere a half-accumulated signal matters.

## Idempotency

A redelivered event is recognised by **identity** — `{source, id}`, which
CloudEvents already requires producers to make unique. `Signals.Dedup` keeps a
bounded set of recent identities per accumulator.

Double-folding isn't a crash. It's a crash-rate signal firing at two instead of
five, quietly, still looking like it works. So the guard has to be reliable
rather than best-effort, and a log position cannot do this job:

- **Events without a position get no protection.** A browser click, a clock
  tick, a PubSub broadcast — most of the event surface — carries no position at
  all.
- **Out-of-order arrivals get dropped.** "Discard anything at or below the
  high-water mark" permanently discards a legitimate event that happens to
  arrive late, which with more than one producer is routine.
- **It assumes a global monotonic sequence**, i.e. a single writer. Backend,
  frontend, and temporal producers are three.

Position is still tracked and persisted, for the different question of *where a
replay should resume*. Answering both questions with one number gets one of
them wrong.

The dedup window is bounded (`:dedup_window`, default 256) because an
accumulator reasons over a window anyway — a duplicate arriving long after that
window has nothing left to corrupt — and unbounded it would leak on a process
meant to run for the life of the system.

## Behaviours

| Behaviour | Decides |
|---|---|
| `Signals.Signal` | What correlates with what |
| `Signals.Store` | Where partial conclusions survive |
| `Signals.Sink` | What happens to a conclusion |

A `Sink` has two audiences and must serve both: other *signals*, which consume
emissions as input, and the world. `Sink.Local` re-routes before broadcasting. A
sink that only broadcasts silently disables every meta-signal, with no error
anywhere.

## Tests

```
mix test
```

79 tests and 14 doctests: routing and fan-out, all three correlation shapes,
meta-signal chaining through a real sink, emission-depth cutoff, identity-based
idempotency including the position-based failure modes, eviction at the window
boundary, restart recovery, and the CloudEvents round-trip.

## Provenance

The model comes from `ADR-025-signal-mental-model-accumulator-not-topic`
— *"A Signal is something that listens to one or many topics. A Signal is not a
topic. You cannot subscribe to a Signal."* The ergonomics come from
a `use Signal` macro in a sibling codebase. The durable projector with
checkpointed positions comes from that codebase's `SignalProjector`.

Added here, from neither: per-signal timer intervals (the topic tables call for
5s through 5min; both implementations hardcoded one), declarative wildcard
`topics/0`, `partition_key/1`, emissions routed back for composition, the depth
cutoff that makes composition safe, and identity-based idempotency.

Fixed: the original `SignalProcess` called `handle_info/2` on signal modules,
but the callback was in neither the behaviour nor the macro and no module
defined it — so any stray message (a monitor `:DOWN`, a late timer) crashed the
accumulator. Here it's a defaulted optional callback.
