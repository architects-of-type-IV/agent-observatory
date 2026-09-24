# Elixir Reasoning Heuristics

Use these heuristics while reasoning about Elixir code. They are design constraints, not merely style rules.

## 1. Start with data, not modules

Before inventing a module, identify the data being transformed.

Ask:

- What shape enters?
- What shape leaves?
- What invariants must hold?
- What states are actually representable?
- Which transformations are permitted?

Prefer thinking:

``` text
input shape
    -> validation
    -> transformation
    -> output shape
```

over:

``` text
Thing
ThingManager
ThingService
ThingProcessor
ThingHandler
```

A module should usually emerge from a coherent set of transformations, not from finding a noun in the requirements.

------------------------------------------------------------------------

## 2. Modules are namespaces for related semantics

Do not treat an Elixir module as a class.

A module:

- does not own instances;
- does not encapsulate mutable object state;
- does not need to represent a real-world noun;
- does not require a corresponding struct;
- does not imply lifecycle or identity.

Think of a module as a **semantic category of related functions**.

Good question:

> Which operations naturally belong together?

Bad question:

> Which class should own this behavior?

For example:

``` elixir
Date
URI
Enum
Map
Path
String
```

These names describe domains of operations, not object-oriented actors.

------------------------------------------------------------------------

## 3. Name the transformation before naming the abstraction

Before creating a new abstraction, describe the transformation in plain language.

For example:

``` text
raw gateway payload -> validated gateway state
```

This might naturally become:

``` elixir
GatewayState.parse/1
```

It does not automatically justify:

``` text
GatewayStateManager
GatewayStateService
GatewayStateProcessor
GatewayStateFactory
```

If the abstraction cannot be explained as a coherent transformation or capability, reconsider it.

------------------------------------------------------------------------

## 4. Shapes come before functions

Identify the valid input shapes before implementing behavior.

Elixir functions are frequently best understood as mappings between shapes:

``` elixir
%{"status" => "online", "id" => id}
    -> {:ok, %Gateway{id: id, online?: true}}
```

Different shapes often imply different function clauses:

``` elixir
def parse(%{"status" => "online"} = data), do: ...
def parse(%{"status" => "offline"} = data), do: ...
def parse(_), do: {:error, :invalid_status}
```

Do not immediately write one generic function and reconstruct the shape internally.

------------------------------------------------------------------------

## 5. Pattern matching is part of the design

Pattern matching is not merely syntax for extracting values.

It expresses:

- valid states;
- valid inputs;
- dispatch;
- decomposition;
- contracts;
- failure boundaries.

Prefer:

``` elixir
def handle({:ok, value}), do: ...
def handle({:error, reason}), do: ...
```

over:

``` elixir
def handle(result) do
  case result do
    ...
  end
end
```

when the distinction naturally belongs at the function boundary.

Move decisions outward into function heads whenever doing so makes the accepted shapes clearer.

------------------------------------------------------------------------

## 6. Function clauses are often the first abstraction

Before inventing:

- strategies;
- handlers;
- command classes;
- visitors;
- factories;
- dispatch tables;

consider whether ordinary function clauses already model the variation.

``` elixir
def normalize(%User{} = user), do: ...
def normalize(%Device{} = device), do: ...
def normalize(%Gateway{} = gateway), do: ...
```

Elixir already has powerful dispatch based on shape and guards.

Do not recreate OO polymorphism unnecessarily.

------------------------------------------------------------------------

## 7. Prefer closed data over hidden behavior

Data should usually make state visible.

Prefer:

``` elixir
{:error, :not_found}
```

over an object whose internal state represents failure.

Prefer:

``` elixir
%Command{action: :open, target: id}
```

over an object carrying methods that eventually reveal what operation it represents.

Visible data is easier to:

- pattern match;
- inspect;
- serialize;
- test;
- transform;
- reason about.

------------------------------------------------------------------------

## 8. Make invalid states difficult to represent

Do not merely ask whether the code validates input.

Ask whether the resulting representation expresses the invariant.

Instead of allowing arbitrary maps throughout the system:

``` elixir
%{
  state: value,
  ...
}
```

consider introducing a struct once the data has crossed a meaningful validation boundary:

``` elixir
%GatewayState{
  status: :online,
  ...
}
```

A struct is useful when it establishes a meaningful shape.

A struct is not justified merely because an OO language would have introduced a class.

------------------------------------------------------------------------

## 9. Structs are data contracts, not objects

A struct should answer:

> Does this data shape deserve a name?

It should not answer:

> What class represents this thing?

Avoid automatically giving every module a struct.

Avoid automatically putting every function operating on a struct into that struct's module.

The appropriate module depends on the semantics of the operation.

------------------------------------------------------------------------

## 10. Prefer transformations over mutation narratives

Describe code as:

``` text
A -> B -> C
```

not:

``` text
create A
modify A
update A
change A again
```

Values do not change.

New values are produced.

This distinction should influence names and architecture.

Prefer concepts such as:

``` text
normalize
decode
encode
validate
merge
derive
reduce
build
parse
format
```

when they accurately describe the transformation.

Avoid mutation-oriented vocabulary unless the operation genuinely concerns an external mutable resource.

------------------------------------------------------------------------

## 11. Separate pure transformations from effects

Determine which part of the problem can be expressed as:

``` elixir
input -> output
```

Keep that logic pure.

Push effects toward explicit boundaries:

``` text
read
decode
transform
validate
persist
```

rather than mixing:

``` text
read + validate + mutate state + log + persist + notify
```

inside one function.

A useful decomposition is:

``` text
functional core
    |
effect boundary
```

Do not introduce processes merely to organize ordinary computation.

------------------------------------------------------------------------

## 12. A process is a runtime property, not an architectural layer

Do not create a `GenServer` because something:

- is important;
- needs a module;
- has state conceptually;
- sounds like a service;
- coordinates functions.

Use a process when the problem requires runtime semantics such as:

- concurrent identity;
- ownership;
- serialization;
- isolation;
- supervision;
- timers;
- message handling;
- retained runtime state.

Ask:

> What property of the runtime requires this to be a process?

If there is no concrete answer, use ordinary functions and data.

------------------------------------------------------------------------

## 13. Process state belongs to the process boundary

When a process is justified, distinguish:

``` text
domain data
```

from:

``` text
process state
```

They are not necessarily the same thing.

A GenServer struct should not automatically become the domain model.

Keep domain transformations independently callable whenever possible:

``` elixir
new_state = Workspace.update(old_state, event)
```

The process can then be responsible only for owning `old_state`.

------------------------------------------------------------------------

## 14. OTP describes failure and lifetime semantics

Do not treat supervision trees as dependency-injection trees.

A supervision tree answers questions such as:

- What lives independently?
- What fails independently?
- What should restart?
- What state survives?
- In what order should components start?
- Which failures should propagate?

Do not organize supervisors according to arbitrary domain taxonomy.

Runtime relationships should justify the tree.

------------------------------------------------------------------------

## 15. Ask who owns mutable state

Whenever the design involves changing state, explicitly identify its owner.

Possible answers include:

- nobody — the value is immutable and passed explicitly;
- a GenServer;
- ETS;
- another process;
- an external database;
- an external system.

Never vaguely say that a module "holds" state.

Modules do not hold runtime state.

------------------------------------------------------------------------

## 16. Prefer explicit return values

Functions should communicate through values.

Common contracts include:

``` elixir
{:ok, value}
{:error, reason}
:ok
:error
```

Do not introduce exceptions, callbacks, mutable containers, or hidden process interaction when an explicit return value adequately describes the result.

The caller should be able to reason from the return shape.

------------------------------------------------------------------------

## 17. Errors are part of the data model

Treat failure shapes as deliberately as success shapes.

Ask:

``` text
What failures can occur here?
Which are expected?
Which are programmer errors?
Which should be represented as values?
```

Do not reflexively rescue exceptions.

Expected domain failures generally deserve explicit values and patterns.

Exceptional conditions should remain exceptional.

------------------------------------------------------------------------

## 18. Use `with` for pipelines that may stop

`with` is useful when several successful transformations must happen sequentially:

``` elixir
with {:ok, decoded} <- decode(raw),
     {:ok, valid} <- validate(decoded),
     {:ok, result} <- transform(valid) do
  {:ok, result}
end
```

Do not use `with` merely because multiple lines return tuples.

Do not add `else` unless translating failures at that boundary is genuinely necessary.

Let existing error shapes propagate when they already express the correct semantics.

------------------------------------------------------------------------

## 19. Use guards for constraints, patterns for structure

Patterns answer:

> What shape is this?

Guards answer:

> Under what additional constraints is this shape valid?

For example:

``` elixir
def percentage(value) when value in 0..100, do: ...
```

Do not replace straightforward guards and patterns with procedural conditionals.

------------------------------------------------------------------------

## 20. Prefer declarative collection transformations

For collection processing, first consider:

- comprehensions;
- `Enum`;
- `Stream`;
- pattern matching;
- recursion when the algorithm genuinely requires it.

Prefer describing the transformation over manually managing intermediate state.

Do not translate loops from imperative languages mechanically.

------------------------------------------------------------------------

## 21. Recursion is a mechanism, not a badge of functional purity

Do not write explicit recursion when `Enum`, `Stream`, or a comprehension states the intent more clearly.

Use recursion when recursive structure is intrinsic to the problem.

The goal is semantic clarity, not demonstrating functional programming techniques.

------------------------------------------------------------------------

## 22. Pipelines should tell a story

A pipeline should represent a meaningful sequence of transformations:

``` elixir
raw
|> decode()
|> normalize()
|> validate()
```

Do not pipeline merely because `|>` exists.

If the pipeline obscures argument roles or creates awkward helper functions purely to support piping, ordinary function calls may be clearer.

------------------------------------------------------------------------

## 23. Avoid generic coordinator vocabulary

Treat names such as these as warning signs:

``` text
Manager
Service
Handler
Processor
Helper
Utils
Coordinator
Engine
Factory
Controller
```

They are not forbidden.

But before using one, ask:

> What exact semantic category does this module represent?

If several unrelated operations are being grouped because they "deal with gateways", the abstraction is probably weak.

Prefer names describing an actual domain, transformation, protocol, representation, or capability.

------------------------------------------------------------------------

## 24. Do not manufacture architectural layers

Elixir does not require equivalents of:

``` text
Controller
Service
Repository
DomainService
Manager
Factory
DTO
Entity
```

These may occasionally be useful, but they should arise from actual boundaries.

Do not import architecture wholesale from Java, PHP, C#, TypeScript, or framework conventions.

Each additional layer must explain what semantic boundary it establishes.

------------------------------------------------------------------------

## 25. Prefer boring functions until complexity demands abstraction

Start with:

``` elixir
def foo(data), do: ...
```

Then let duplication, variation, runtime requirements, or semantic boundaries reveal the needed abstraction.

Do not predict hypothetical future abstractions.

Elixir makes extracting functions and modules cheap.

Use that advantage.

------------------------------------------------------------------------

## 26. Behaviour means contract, not inheritance

A behaviour defines a callback contract.

It should model a genuine family of implementations.

Do not introduce a behaviour merely:

- to make something mockable;
- because there is one implementation;
- to simulate interfaces from OO languages;
- because future implementations might exist.

First establish that meaningful substitutability exists.

------------------------------------------------------------------------

## 27. Protocols are about data polymorphism

Use a protocol when an operation should vary according to the type of its first argument.

Think:

``` text
same semantic operation
different data types
```

Do not use protocols as generic interface mechanisms.

Do not create protocols merely to avoid writing ordinary function clauses.

------------------------------------------------------------------------

## 28. Explicit dispatch is often perfectly good

This:

``` elixir
def execute(:start, state), do: ...
def execute(:stop, state), do: ...
def execute(:reset, state), do: ...
```

may be better than dynamically discovering modules implementing:

``` text
StartCommand
StopCommand
ResetCommand
```

Do not confuse indirection with extensibility.

------------------------------------------------------------------------

## 29. Data boundaries deserve names more often than orchestration does

Good candidates for modules often include concepts such as:

``` text
URI
Packet
Frame
GatewayState
Measurement
Schedule
Path
Token
Command
Configuration
```

because these define meaningful data semantics.

Weak abstractions often describe somebody "doing something to something":

``` text
GatewayManager
PacketProcessor
StateHandler
CommandService
```

Prefer naming **what the information means** over naming imaginary actors.

------------------------------------------------------------------------

## 30. Let the caller determine context

Do not make deeply nested functions aware of:

- HTTP;
- Phoenix;
- CLI;
- GenServer;
- database;
- logging;
- telemetry;

unless those concerns actually belong there.

Transformations should operate on the smallest meaningful input.

Context belongs near boundaries.

------------------------------------------------------------------------

## 31. Framework boundaries are not domain boundaries

Phoenix controllers, LiveViews, Ecto schemas, GenServers, and Oban workers are integration mechanisms.

Do not allow their APIs to define the entire application model.

Ask:

> If this code were called without Phoenix/Ecto/OTP, what part would still describe the actual problem?

That part often deserves to remain independent.

------------------------------------------------------------------------

## 32. Ecto schemas are not automatically domain models

An Ecto schema describes persistence-related structure.

Do not automatically make it responsible for every domain operation involving the same data.

Database representation and domain semantics may coincide, but that should be an intentional decision.

------------------------------------------------------------------------

## 33. Do not create wrappers without semantic gain

A function such as:

``` elixir
def get_user(id), do: Repo.get(User, id)
```

adds little unless it establishes something meaningful such as:

- a domain-specific query;
- authorization;
- normalization;
- a stable application boundary;
- a different return contract.

Every wrapper should earn its existence.

------------------------------------------------------------------------

## 34. Ask whether an abstraction removes decisions

A good abstraction makes callers know less.

A bad abstraction merely moves code somewhere else.

Evaluate an abstraction by asking:

> What decisions no longer need to be made by its callers?

If the answer is "none", the abstraction may only be indirection.

------------------------------------------------------------------------

## 35. Prefer semantic compression over structural expansion

Good abstractions reduce the number of concepts necessary to understand the system.

If solving a problem introduces:

``` text
5 modules
3 behaviours
2 structs
1 supervisor
```

where the original problem consisted of three transformations, reconsider the design.

The abstraction should compress understanding.

------------------------------------------------------------------------

## 36. Preserve information until there is a reason to discard it

When transforming data, avoid prematurely converting rich values into booleans, generic strings, or ambiguous atoms.

Prefer representations that preserve distinctions useful for subsequent pattern matching.

Information destroyed early often reappears later as conditionals.

------------------------------------------------------------------------

## 37. Model finite states explicitly

If something has a finite set of meaningful states, represent those states directly:

``` elixir
:connecting
:connected
:disconnecting
:disconnected
```

or with distinct shapes when states contain different information.

Avoid combinations of independent booleans that permit impossible states:

``` elixir
%{
  connected?: true,
  disconnected?: true,
  connecting?: true
}
```

Shape design is state-machine design.

------------------------------------------------------------------------

## 38. Different states may deserve different shapes

Do not force every state into one universal struct containing many nullable fields.

Sometimes:

``` elixir
{:connecting, started_at}
{:connected, socket}
{:failed, reason}
```

expresses the domain better than:

``` elixir
%Connection{
  state: ...,
  started_at: nil,
  socket: nil,
  reason: nil
}
```

Pattern matching becomes stronger when shapes carry semantic meaning.

------------------------------------------------------------------------

## 39. Avoid boolean blindness

A boolean often loses useful meaning.

Instead of:

``` elixir
validate(data) :: boolean()
```

consider:

``` elixir
{:ok, validated}
{:error, reason}
```

Instead of passing:

``` elixir
true
```

consider whether:

``` elixir
:enabled
```

or a richer shape expresses the intent better.

Do not make callers reconstruct meaning from anonymous booleans.

------------------------------------------------------------------------

## 40. Public APIs should expose semantic shapes

A public function's arguments and return values constitute its API.

Prefer:

``` elixir
Gateway.connect(gateway, credentials)
```

over:

``` elixir
Gateway.connect(gateway, true, false, 3, nil)
```

Use meaningful data structures when several values form one concept.

Do not hide weak APIs behind documentation.

------------------------------------------------------------------------

## 41. Pattern matching can replace defensive programming

If a function only makes sense for:

``` elixir
%Gateway{status: :online}
```

consider expressing that directly.

Do not accept arbitrary data and then repeatedly ask whether it is usable.

Make function heads document assumptions.

------------------------------------------------------------------------

## 42. Do not make every function total

It is sometimes correct for a private function to accept only the shape guaranteed by its caller.

Do not defensively add catch-all clauses everywhere.

A catch-all may conceal a programming error that should instead crash.

Use explicit error returns for expected failures.

Use crashes for violated internal assumptions when appropriate.

------------------------------------------------------------------------

## 43. "Let it crash" does not mean "ignore errors"

Distinguish:

``` text
expected domain failure
```

from:

``` text
unexpected process failure
```

OTP supervision handles the latter.

It does not remove the need to model the former.

------------------------------------------------------------------------

## 44. Supervision is not error handling

Do not use retries and restarts to compensate for incorrectly modeled domain failures.

A supervisor restores runtime components.

It does not decide whether:

``` text
invalid password
missing device
malformed payload
insufficient permission
```

is acceptable domain behavior.

------------------------------------------------------------------------

## 45. Concurrency should follow independence

Ask:

> Which work is genuinely independent?

Only then decide whether concurrency is useful.

Do not create tasks, processes, or message passing simply because BEAM makes concurrency inexpensive.

Cheap does not mean semantically justified.

------------------------------------------------------------------------

## 46. Messages should describe events or requests

Process messages should carry explicit meaning.

Prefer:

``` elixir
{:gateway_connected, gateway_id}
{:update_state, new_state}
```

over vague messages such as:

``` elixir
{:update, data}
{:handle, thing}
```

Message shapes form a protocol.

Treat them accordingly.

------------------------------------------------------------------------

## 47. A mailbox is an API

For every receiving process, reason about:

- accepted message shapes;
- ordering;
- ownership;
- backpressure;
- unexpected messages;
- synchronous versus asynchronous semantics.

Do not treat `send/2` as a generic function call.

Message passing changes the semantics of the system.

------------------------------------------------------------------------

## 48. Prefer references over global names

Do not register every process by a global atom merely because named processes are convenient.

Ask whether callers truly need identity-based discovery.

Passing PIDs, references, Registry keys, or explicit dependencies may preserve clearer ownership.

------------------------------------------------------------------------

## 49. Test transformations independently from infrastructure

If business behavior requires starting:

- Phoenix;
- a supervisor;
- a GenServer;
- a database;

just to test a transformation, inspect the design.

Pure domain transformations should normally be directly testable.

Test process semantics separately from transformation semantics.

------------------------------------------------------------------------

## 50. Examples are evidence of shapes

When requirements provide examples, do not merely reproduce their control flow.

Extract:

- recurring shapes;
- invariants;
- variation points;
- transformations;
- failure cases.

Examples should inform the model, not become templates copied literally.

------------------------------------------------------------------------

# Reasoning Order

Before writing Elixir code, reason in this order:

``` text
1. What is the input data?
2. What are its possible shapes?
3. What invariants exist?
4. What should the output shapes be?
5. What transformations connect them?
6. Which distinctions belong in function heads?
7. Which constraints belong in guards?
8. Which failures are expected values?
9. Which logic can remain pure?
10. Where are the actual side-effect boundaries?
11. Is runtime state required?
12. If so, who owns it?
13. Is a process actually required?
14. What failure/lifetime semantics justify OTP?
15. Only now: which modules make these semantics easier to understand?
```

Do not reverse this order by inventing an architecture first.

# Abstraction Test

Before introducing any module, struct, behaviour, protocol, GenServer, supervisor, macro, or architectural layer, answer:

``` text
What semantic distinction does this abstraction make explicit?
```

If there is no precise answer, do not introduce it yet.

# Naming Test

Before naming a module, ask:

``` text
Is this the name of a coherent domain of operations,
or have I invented an actor because I am thinking in objects?
```

Be suspicious of:

``` text
Manager
Service
Processor
Handler
Helper
Util
Factory
Coordinator
Engine
```

Prefer names derived from:

``` text
data
representation
protocol
transformation
domain concept
capability
boundary
```

# Final Review

Before presenting Elixir code, inspect it again and ask:

``` text
Did I import an OO abstraction unnecessarily?

Did I invent modules before understanding the data?

Could function clauses express this variation directly?

Are important shapes hidden inside generic maps or conditionals?

Could pattern matching move closer to the function boundary?

Did I introduce runtime state where immutable data would suffice?

Did I introduce a process without requiring process semantics?

Did I mix pure transformations with effects?

Does every abstraction reduce the amount a caller must understand?

Can any module disappear without losing semantic information?
```

The target is not the smallest number of lines.

The target is the **smallest set of concepts that accurately represents the problem**.
