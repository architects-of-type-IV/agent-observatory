# Ichor Ash Architecture

This document is intentionally boundary-first, not naming-first.

The previous failure mode in `lib/ichor` was not just too many modules. It was freezing weak ideas into module names too early. That created structures that now have to be defended because they exist, not because they model the app correctly.

This document avoids introducing new product nouns unless they already clearly exist in the app.

## Rule

Do not create a named module just because there is code.

A thing gets a stable Ash name only when all of these are true:

- it is visible in the product model
- it has durable rules or relationships
- it is queried independently
- it is mutated independently
- it will still make sense after current implementation details change

If those are not true, keep it as:

- an action
- an embedded resource
- a calculation
- an aggregate
- a notifier
- a runtime module
- or a private function

## What The UI Actually Has

The current UI exposes five slices:

- `/fleet`
- `/workshop`
- `/pipeline`
- `/mes`
- `/signals`

Those reduce to four ownership areas:

- fleet operations
- factory/project execution
- observability/read models
- signals/pubsub

That is the architecture. Names should follow later.

## What Has Now Revealed Itself

These are no longer guesses.

### Workshop

The Workshop is where teams are authored.

- `blueprint` is a frontend term
- in backend/storage terms this is a team
- a team has many members
- each member uses an agent type
- each member can add extra instructions on top of the shared agent-type instructions
- the team includes how agents communicate
- the team should include which Ash AI tools are available to the agents
- prompt building is part of agent construction, not a separate concern

So the stable backend model is:

- team
- team member
- agent type

When a team is spawned, each agent should receive:

- its own prompt
- communication instructions
- teammate identity and routing information
- MCP usage instructions
- tmux/session identity
- the allowed Ash AI tools for that team setup

That means the team definition owns more than layout. It owns the runtime contract for spawning.

### MES

`/mes` is project planning and project lifecycle.

- projects start as project briefs
- `genesis` / `node` is your pet name for that MES project lifecycle object
- it is not a git project
- it should not be treated as a separate durable concept unless the lifecycle truly demands it
- projects accumulate planning artifacts such as ADRs and use cases
- planning is advanced by spawning teams for modes like mode A and mode B

The API needs to reveal that these are all team spawns from a blueprint/team-definition surface:

- `spawn_team("mes")`
- `spawn_team("mode-a")`
- `spawn_team("mode-b")`

The current API shape is incidental. The target shape should be `spawn_team/1`.

### Pipeline

Planned projects become DAG work.

- tasks are created from MES project specs/planning output
- tasks are organized into DAG structure
- work is divided into waves
- teams/agents execute wave-ready work on `/pipeline`

Important:

- tasks belong to the app/domain model
- the DAG is derived from tasks
- `tasks.jsonl` is a synchronization boundary, not the source domain model

Some projects keep `tasks.jsonl` in their own git repo. That file must stay in sync with the app because this system operates across multiple repositories and working directories.

So the pipeline is the execution continuation of MES, not a separate business domain.

### Signals

The signals page is the reactive core of the whole system.

- it is the topic stream
- it is the pub/sub boundary
- everything important should be able to react to it
- Archon should consume it as the master coordinator for team activity

Signals are not just logging. They are the nervous system.

### Infra

Everything else exists to support those product truths.

- tmux is transport/runtime infrastructure
- MCP is tool/execution infrastructure
- agent agnosticism is an infrastructure goal

Those should not be allowed to dominate the domain model.

## Frontend Terms

Some names are useful on the frontend but should not become backend domain anchors.

### `fleet`

`fleet` is the UI view of all discovered and spawned agents.

It is a projection, not a durable entity.

### `blueprint`

`blueprint` is the Workshop authoring term.

In backend and SQL terms, this is a team.

That means the durable model should center on:

- team
- team member
- agent type

not on `blueprint` as a business noun.

## The Current Problem

`lib/ichor` is at 128 files.

The issue is not file count alone. The issue is that many files exist only because boundaries are weak:

- giant tool wrapper resources
- giant runtime/orchestration modules
- preparations that reconstruct missing ownership
- gateway resources attached to whichever domain touched them first
- structured nested data stored as raw maps
- direct resource calls from the UI instead of domain boundaries

Large hotspots:

- [`lib/ichor/tools/runtime_ops.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/runtime_ops.ex)
- [`lib/ichor/tools/project_execution.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/project_execution.ex)
- [`lib/ichor/tools/genesis.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/genesis.ex)
- [`lib/ichor/projects/runner.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/runner.ex)
- [`lib/ichor/projects/runtime.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/runtime.ex)
- [`lib/ichor/projects/spawn.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/spawn.ex)

These are strong signals that the app is compensating for poor domain modeling with orchestration code.

## Boundary Decisions

### Fleet Area

This area owns what the `/fleet` and `/workshop` pages actually manipulate:

- live agents
- teams
- authored teams
- reusable agent defaults
- operator interventions
- fleet-issued scheduled work
- fleet-owned outbound delivery tracking

This area should not invent extra entity names unless the UI or business rules demand them.

What should become resources:

- the currently running agent concept
- the team concept
- the team-member concept, because it carries team-specific instructions over an agent type
- the reusable agent-type concept
- the intervention audit concept
- the persisted scheduled command concept
- the persisted delivery/retry concept

What should not become top-level resources:

- workshop canvas edges if they only live inside a team
- communication rules if they only live inside a team definition
- per-team tool exposure if it only lives inside a team definition

Those should be embedded resources unless they later prove to be independently queried and mutated.

Current raw-map anti-pattern:

- [`lib/ichor/control/blueprint.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/control/blueprint.ex)

That file is currently carrying the frontend name, but the backend model should converge on `team`.

The durable question is not "keep blueprint or not". The durable question is:

- `team` as the parent resource
- `team member` as either a real child resource or an embedded resource
- `agent type` as the reusable default source

Because each member has team-specific instructions layered on top of the agent-type defaults, `team member` is a strong candidate to be a real resource rather than a raw embedded draft.

This resource should be able to drive a single public spawn action:

- `spawn_team(name)`

That action should:

- load the team definition
- load the team members
- merge agent-type defaults with per-team-member overrides
- build agent prompts
- inject communication instructions
- inject teammate/session/MCP data
- scope allowed Ash AI tools
- launch the team

### Factory Area

This area owns what `/mes` and `/pipeline` actually do:

- project intake
- planning artifacts
- tasks created from project specs
- DAG derivation from those tasks
- readiness checks
- execution runs
- execution jobs
- build/load lifecycle

`/mes` and `/pipeline` are not separate domains. One creates and advances work, the other displays and operates the execution state of that same work.

What should become resources:

- project brief / subsystem project
- task
- execution run
- execution job

What should be reconsidered carefully before naming:

- whether `node` is actually just the MES project under a pet name
- the current unified artifact model
- the current unified roadmap item model

The current problem is not only naming. It is also possible that the code has split one real concept into multiple named shells.

The first place to challenge that is the current project/node split:

- [`lib/ichor/projects/project.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/project.ex)
- [`lib/ichor/projects/node.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/node.ex)

If `genesis` / `node` is just the MES project under a pet name, the durable model should collapse toward one project resource with planning state, rather than preserving two nouns because the code currently has them.

The other problem is hiding multiple concepts behind `kind`:

- [`lib/ichor/projects/artifact.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/artifact.ex)
- [`lib/ichor/projects/roadmap_item.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/roadmap_item.ex)

You do not need to choose the final names yet. But you do need to decide which of these are truly separate concepts with separate rules.

Use this rule:

- if two kinds have different validations, different relationships, different creation flows, and different read surfaces, they should not be one resource
- if they mostly share lifecycle and differ only in presentation, they can stay unified

For this repo, the current artifact split is likely too collapsed. The surrounding code branches too much.

The important thing is that team spawning for planning modes is still team spawning.

That means planning mode launches should not grow their own unrelated API. They should be driven by the same spawn surface:

- `spawn_team("mes")`
- `spawn_team("mode-a")`
- `spawn_team("mode-b")`
- `spawn_team("mode-c")`

The important task rule is:

- the database/app model owns tasks
- `tasks.jsonl` must be kept in sync for repo-local workflows
- file sync is infrastructure/action logic, not a separate business entity

### Observability Area

This area owns durable facts and queryable read models for the dashboard:

- events
- sessions
- messages
- errors
- intervention audit records

This area should not own the live signal system itself.

The current `Observability.Task` looks suspiciously like a projection standing in for weak ownership elsewhere:

- [`lib/ichor/observability/task.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/observability/task.ex)

It should stay only if the dashboard really needs a separate read model. Otherwise task state belongs with the work/execution side.

The preparations in:

- [`lib/ichor/observability/preparations/load_tasks.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/observability/preparations/load_tasks.ex)
- [`lib/ichor/observability/preparations/load_messages.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/observability/preparations/load_messages.ex)
- [`lib/ichor/observability/preparations/load_errors.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/observability/preparations/load_errors.ex)

exist because the domain model is compensating for upstream ambiguity.

### Signals Area

This area owns:

- signal catalog
- signal emission surface
- signal transport
- signal buffering

It is small by design.

It should not be merged into observability just because both are read from the dashboard.

## What Should Lose Its Name Entirely

The synthetic MCP/action wrapper layer should not survive as named business resources.

These are packaging modules, not entities:

- [`lib/ichor/tools/runtime_ops.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/runtime_ops.ex)
- [`lib/ichor/tools/project_execution.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/project_execution.ex)
- [`lib/ichor/tools/genesis.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/genesis.ex)
- [`lib/ichor/tools/agent_memory.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/agent_memory.ex)
- [`lib/ichor/tools/archon/memory.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/archon/memory.ex)

Those actions should move onto the owning domains and resources.

Ash AI should attach to the real ownership boundaries, not to a fake "tools" boundary.

## PubSub And Notifiers

The current custom notifier:

- [`lib/ichor/signals/from_ash.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/from_ash.ex)

is directionally right, but it is becoming a global translation registry.

Use this rule:

- if a resource mutation only needs straightforward topic publication, use `Ash.Notifier.PubSub`
- if it must emit into the app's signal catalog with custom event naming, keep the custom notifier
- do not centralize unrelated resource mappings forever in one file

## Dashboard Boundary Rule

The dashboard should stop treating resource modules as its public API.

Current examples:

- [`lib/ichor_web/live/dashboard_state.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_state.ex)

The LiveView should call domains and read actions shaped for the UI. If the UI needs a combined view, create a real read action or a projection. Do not keep rebuilding the screen from a scatter of unrelated resource calls.

## How To Reduce Module Count Without Lying

You asked for 50-60 modules. That is possible only if whole categories disappear.

The big deletions are:

1. Remove the synthetic `tools/` resource layer.
2. Remove preparation modules that only rebuild missing boundaries.
3. Remove raw-map state helpers by replacing them with embedded resources.
4. Shrink orchestration god modules by moving stable rules into Ash actions and resources.
5. Stop naming temporary implementation clusters as permanent concepts.

The wrong way to get to 50-60 is to merge unrelated things under broad names.

The right way is:

- fewer fake public surfaces
- fewer wrapper layers
- fewer placeholder concepts
- more ownership in the actual resources

## Migration Order

### 1. Fix boundaries before names

- Decide the four ownership areas in code.
- Do not finalize deeper module names yet.

### 2. Delete the synthetic tools boundary

- Move MCP tool exposure to the owning domains.
- Update Archon to mount domain tools directly.

### 3. Fix Workshop persistence

- Keep blueprint as the top-level resource.
- Convert nested arrays of maps into embedded resources.

### 4. Rework the planning/execution side

- Decide which current `kind` values are truly separate concepts.
- Split only where the rules are actually distinct.

### 5. Rebuild dashboard reads

- Use domain-level reads shaped for the page.
- Delete preparation shims where possible.

### 6. Then finalize names

Only after the ownership lines are stable should you pick the final module names.

## Immediate Next Step

The next practical step is not renaming modules.

It is producing a boundary matrix for the current resources and runtimes:

- keep as resource
- turn into embedded resource
- turn into domain action
- keep as runtime module
- delete after consolidation

That will let you reduce the app without repeating the same mistake under nicer names.
