# Full Umbrella Restructure Architecture

## Purpose

This document is the implementation baseline for converting the current single-app
`ichor` project into a true Mix umbrella.

The restructure target is:

1. reusable pure Elixir libraries
2. Ash domain apps and moderate Ash subdomains
3. app-local orchestration/runtime shells
4. one Phoenix product app

The guiding rule is unchanged from `ash-elixir-expert.md`:

- durable business entities and business capabilities belong in Ash domains
- pure transformations and reusable contracts belong in pure Elixir libraries
- orchestration, runtime coordination, GenServers, routers, monitors, and supervisors
  remain plain Elixir shells in the product app unless they later prove reusable

## End-State Apps

### Pure Library Apps

| App | Owns | Must Not Own |
| --- | --- | --- |
| `ichor_signals` | signal catalog, message contracts, runtime emit/subscribe adapters, notifier integration | Phoenix handlers, product-only supervisors |
| `ichor_mesh` | `DecisionLog`, reusable DAG/topology core, mesh schemas/validators | dashboard publishers, product-only PubSub orchestration |
| `ichor_memory_core` | memory block/recall/archival models, pure transformations, storage behaviors | the app-specific `MemoryStore` GenServer shell |
| `ichor_tmux_runtime` | launch specs, tmux script generation, tmux launching, generic cleanup contracts | fleet registration, app-specific signals, supervisor ownership |
| `ichor_dag_core` | graph/validator/loader/exporter/pure DAG logic | run supervisors, product lifecycle orchestration |

### Ash Domain Apps

| App | Owns | Moderate Subdomains |
| --- | --- | --- |
| `ichor_fleet` | `Agent`, `Team`, fleet read models | none initially |
| `ichor_activity` | `Message`, `Task`, `Error` | `Activity.Messages`, `Activity.Tasks` |
| `ichor_events` | persisted event/session resources | `Events.Sessions` |
| `ichor_costs` | token/cost usage resources | `Costs.Usage` |
| `ichor_workshop` | design-time blueprint resources | `Workshop.Blueprints` |
| `ichor_mes` | persisted MES resources | none initially beyond `Project` |
| `ichor_genesis` | planning resources | `Genesis.Artifacts`, `Genesis.Roadmap` |
| `ichor_dag` | persisted DAG execution resources | none initially |

### Product App

The product app remains the only Phoenix-facing application and owns:

- Phoenix endpoint, router, controllers, LiveViews, components
- OTP application start order
- runtime orchestration shells
- monitors, janitors, bridges, routers, watchdogs
- temporary compatibility facades
- AshAi tool integration boundaries

The product app depends on the extracted library apps and Ash domain apps.

## Dependency Rules

### Allowed

- product app -> pure libs
- product app -> Ash domain apps
- tool integration modules -> pure libs + Ash domain apps
- Ash domain apps -> pure libs
- pure libs -> other pure libs only when the dependency is contract-level and stable

### Forbidden

- pure libs -> Phoenix or LiveView
- pure libs -> product app
- Ash domain apps -> product runtime shells
- extracted apps -> direct dependencies on dashboard handlers or controller modules
- tmux runtime library -> fleet registration or product signal policy

## Runtime Shells That Stay in the Product App

These remain plain Elixir boundaries even after extraction:

- `Ichor.Archon.Chat`
- `Ichor.SwarmMonitor`
- `Ichor.Fleet.Lifecycle`
- `Ichor.Gateway.Router`
- `Ichor.MemoriesBridge`
- `Ichor.QualityGate`
- `Ichor.AgentMonitor`
- `Ichor.PaneMonitor`
- `Ichor.Operator`
- `Ichor.Mes.RunProcess`
- `Ichor.Dag.RunProcess`
- supervisors and application startup wiring

## Extraction Waves

### Wave 1: Inventory and Compatibility

- classify every `lib/ichor` module by target app and target category
- preserve all public entrypoints with compatibility facades
- add characterization tests on public seams before moving code

### Wave 2: Umbrella Bootstrap

- convert the repo to a Mix umbrella
- move the current app into the product app with no behavior changes
- keep current config, runtime startup order, route names, Ash code interfaces, and MCP tool names

### Wave 3: Pure Libraries First

Extract in this order:

1. `ichor_signals`
2. `ichor_mesh`
3. `ichor_memory_core`
4. `ichor_tmux_runtime`
5. `ichor_dag_core`

Each extraction must introduce stable public contracts and leave product-app compatibility modules in place.

### Wave 4: Ash Domains

Extract in this order:

1. `ichor_genesis`
2. `ichor_dag`
3. `ichor_workshop`
4. `ichor_activity`
5. `ichor_events`
6. `ichor_costs`
7. `ichor_mes`
8. `ichor_fleet`

### Wave 5: Tool and Facade Normalization

- rebuild `Ichor.AgentTools` as a tool-facing integration app over extracted libs/domains
- rebuild `Ichor.Archon.Tools` the same way
- keep tool names and current external contracts stable

### Wave 6: Product Runtime Cleanup

- refactor remaining shells to depend only on extracted app contracts
- remove obsolete compatibility shims only after caller migration and tests are complete

## Function Splitting Rules

Every moved or refactored module should follow these shape rules:

- Shell modules keep public API and delegate parsing, normalization, formatting, persistence, and side effects to collaborators.
- Ash resources keep DSL, validations, relationships, actions, and code interfaces only. Push pure transformations into sibling modules.
- Monitors split into discovery, analysis, mutation, and broadcast collaborators.
- Router-like modules split validation, resolution, delivery, audit, and side-effect handlers.
- GenServer shells keep state ownership and callback sequencing only. Pure transformations and storage logic move out.
- Extracted pure libraries expose explicit contracts and tagged tuple return shapes.

## Compatibility Rules

The following public surfaces remain callable until the final cleanup wave:

- `Ichor.AgentSpawner`
- `Ichor.Mes.TeamSpawner`
- `Ichor.Archon.Chat`
- `Ichor.AgentTools`
- `Ichor.Archon.Tools`
- current Ash code interfaces on resources

Do not rename:

- Phoenix routes
- LiveView module names
- MCP tool names
- signal names
- Ash code interfaces

## Acceptance Criteria

The final umbrella migration is complete only when:

- the umbrella root compiles cleanly
- `mix precommit` passes from the umbrella root
- current web behavior is preserved
- current MCP surfaces are preserved
- current Ash code interfaces are preserved
- signal names and runtime flows remain stable
- product runtime shells depend only on extracted app contracts
