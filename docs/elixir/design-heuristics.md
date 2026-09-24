# Elixir Design Heuristics

When designing or generating Elixir, reason according to these rules.

1. **Start with data shapes.** Identify inputs, outputs, valid states, invariants, and failure shapes before designing modules.
2. **Reason in transformations.** Model the problem primarily as transformations from one immutable value to another.
3. **Do not think in objects.** Modules are not classes, structs are not objects, behaviours are not interfaces, and GenServers are not services.
4. **Let modules emerge from semantics.** A module should group a coherent domain of operations. Do not create modules merely because requirements contain nouns.
5. **Name data before actors.** Prefer names describing data, protocols, representations, capabilities, or transformations over invented actors such as `Manager`, `Service`, `Processor`, or `Handler`.
6. **Use function heads as design boundaries.** Express meaningful differences in input shape through function clauses and pattern matching before introducing conditional logic or polymorphic abstractions.
7. **Use patterns for structure and guards for constraints.** Do not reconstruct known shapes inside function bodies.
8. **Make shapes explicit.** Prefer meaningful tuples, structs, and atoms over generic maps, nullable fields, anonymous booleans, or positional flags.
9. **Make invalid states difficult to represent.** Design representations so impossible or contradictory states are excluded where practical.
10. **Treat errors as data when they are expected.** Model expected failures explicitly with meaningful return shapes. Do not use exceptions for ordinary domain outcomes.
11. **Keep pure transformations pure.** Separate deterministic data transformation from IO, persistence, processes, logging, telemetry, networking, and framework concerns.
12. **Do not create processes for organization.** Introduce a process only when runtime semantics require ownership, concurrency, isolation, serialization, messaging, timers, or supervision.
13. **Separate domain state from process state.** A GenServer owning data does not make its internal state the domain model.
14. **Use OTP for lifetime and failure semantics.** Supervision trees describe runtime ownership, restart boundaries, and failure propagation, not application layering or dependency injection.
15. **Prefer ordinary functions before advanced abstractions.** Before introducing behaviours, protocols, macros, callbacks, dynamic dispatch, or registries, determine whether function clauses already solve the problem clearly.
16. **Do not manufacture architectural layers.** Introduce repositories, services, coordinators, adapters, DTOs, command layers, or similar concepts only when they establish a real semantic or system boundary.
17. **Every abstraction must remove decisions from callers.** If an abstraction merely relocates code or introduces indirection, reconsider it.
18. **Prefer semantic compression.** The design should reduce the number of concepts needed to understand the problem. More modules, processes, and indirection require justification.
19. **Let boundaries own context.** HTTP, Phoenix, Ecto, CLI, database, telemetry, and process concerns should remain near their respective boundaries unless they are intrinsic to the domain operation.
20. **Choose the smallest accurate model.** Optimize for the smallest set of concepts that faithfully represents the domain, its data shapes, transformations, effects, runtime semantics, and failures.

Before presenting code, verify:

- Did I invent modules before understanding the data?
- Did I import an OO abstraction?
- Are important states hidden inside generic structures or conditionals?
- Could pattern matching move into function heads?
- Did I introduce state or a process unnecessarily?
- Are pure transformations mixed with effects?
- Does each abstraction establish a precise semantic boundary?
- Could anything be removed without losing meaning?

If yes, simplify before answering.
