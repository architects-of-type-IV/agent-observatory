# Elixir Design Reasoning Protocol

Before designing modules or writing implementation code, derive the solution in the following order.

## Phase 1 — Discover the data

Identify every meaningful input and output shape.

For each value determine:

- What does it mean?
- What information does it contain?
- Which variants exist?
- Which fields are mandatory?
- Which states are impossible?
- Which invariants must already hold?

Express representative shapes explicitly.

Example:

```elixir
%{
  "device_id" => device_id,
  "state" => "online"
}
```

may become:

```elixir
%DeviceState{
  device_id: device_id,
  status: :online
}
```

Do not choose modules yet.

---

## Phase 2 — Discover the transformations

Describe the required behaviour without architecture.

Use statements of the form:

```text
A -> B
```

or:

```text
A + B -> C
```

Examples:

```text
raw payload -> decoded payload

decoded payload -> validated device state

device state + event -> new device state
```

Distinguish transformations from effects.

Example:

```text
payload -> device state          PURE

device state -> database         EFFECT

event + state -> new state       PURE

receive event                    EFFECT
```

---

## Phase 3 — Discover the variants

Find places where behaviour differs according to data shape.

Before using conditionals, callbacks, behaviours, protocols, strategies, or dynamic dispatch, test whether function clauses describe the variants directly.

Prefer:

```elixir
def apply_event(state, %Connected{} = event), do: ...
def apply_event(state, %Disconnected{} = event), do: ...
```

when the behaviour genuinely depends on event shape.

Ask:

> Is this polymorphism, or simply pattern matching?

Use the simpler mechanism.

---

## Phase 4 — Discover failure shapes

For each transformation ask:

- What can fail?
- Is this failure expected?
- Is it caused by external input?
- Is it a violated internal invariant?
- Must the caller distinguish different failures?

Model expected failures explicitly.

Example:

```elixir
{:ok, state}
{:error, :unknown_device}
{:error, {:invalid_state, value}}
```

Do not catch programmer errors merely to return `{:error, reason}`.

---

## Phase 5 — Discover ownership

Only now ask whether anything requires mutable runtime state.

For every changing value identify its owner:

```text
no owner
caller
GenServer
Agent
ETS
database
external system
```

If immutable values can simply be passed through functions, prefer that.

Do not create a process merely because the domain contains the concept of state.

---

## Phase 6 — Discover concurrency

Ask:

- Which activities truly happen independently?
- Which operations must be serialized?
- Which component requires an independent lifetime?
- Which state must survive between calls?
- Which failures should be isolated?

Only introduce processes where these runtime properties exist.

Cheap concurrency is not justification for concurrency.

---

## Phase 7 — Discover failure boundaries

If processes exist, determine:

```text
what may fail independently?

what should restart?

what should terminate together?

what state survives restart?

who owns child lifetime?
```

Derive supervision from these answers.

Do not derive supervision from domain taxonomy.

---

## Phase 8 — Discover semantic categories

Only after the previous phases identify modules.

Group functions according to coherent semantics.

A useful module should answer:

> What category of operations does this represent?

Examples:

```text
Packet
URI
Schedule
DeviceState
Credentials
Configuration
Measurement
```

Be suspicious when the answer sounds like:

```text
the thing that manages X

the service responsible for X

the processor that handles X
```

Those descriptions often indicate that the data model has not yet been discovered.

---

## Phase 9 — Test every abstraction

For every proposed:

- module;
- struct;
- process;
- behaviour;
- protocol;
- macro;
- supervisor;
- callback;
- abstraction layer;

ask:

> What semantic distinction becomes explicit because this exists?

Then ask:

> What decisions no longer need to be made by its callers?

If neither question has a precise answer, remove the abstraction.

---

## Phase 10 — Construct the implementation

Only now write code.

Prefer, in order:

1. pattern matching;
2. function clauses;
3. guards;
4. ordinary functions;
5. `Enum`, comprehensions, or `Stream`;
6. structs when a shape deserves an explicit contract;
7. modules when a semantic category has emerged;
8. processes when runtime semantics require them;
9. behaviours or protocols when genuine substitutability exists;
10. macros only when compile-time abstraction provides material value.

This ordering is a heuristic, not a rigid hierarchy.

Its purpose is to resist reaching for stronger mechanisms before simpler language semantics have been exhausted.

---

# Final Compression Pass

Before finishing, attempt to remove concepts.

Ask:

```text
Can a module become a function?

Can a process become immutable data?

Can a callback become a function clause?

Can a behaviour become explicit dispatch?

Can a generic map become a meaningful shape?

Can a conditional become pattern matching?

Can an architectural layer disappear?

Can framework knowledge move outward toward a boundary?
```

Keep removing concepts until further removal would obscure important semantics.

The goal is not minimal code.

The goal is minimal conceptual surface area.
