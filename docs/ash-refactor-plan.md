# Ichor Ash Refactor Plan

This plan assumes the frontend is the acceptance suite.

That means every phase must preserve the visible behavior of:

- `/pipeline`
- `/fleet`
- `/workshop`
- `/signals`
- `/mes`

No phase is "done" because the backend feels cleaner. A phase is done when the page behavior still works and the backend category being removed is actually gone.

## Core Principle

Refactor by deleting boundary mistakes in descending leverage order.

Do not start by renaming everything.
Do not start by splitting every big file.
Do not start by introducing new nouns.

Start by removing the structures that force entanglement:

1. synthetic tool boundary
2. raw-map workshop modeling
3. preparation shim layers
4. orchestration god-modules
5. over-collapsed `kind` resources

## Phase 0: Lock The Acceptance Surface

This is not a code phase. It is the baseline.

For each page, record the required visible behaviors.

### `/fleet`

- fleet roster renders
- agent detail panel renders
- comms tab loads messages
- feed tab loads grouped events
- pause/resume/shutdown still work
- tmux connect/focus still work

### `/workshop`

- presets load
- adding/removing agents works
- dragging agents works
- spawn links render
- comm rules render
- blueprints save/load/delete
- agent types create/edit/delete
- launch team works

### `/pipeline`

- watched projects render
- task board renders
- task selection works
- DAG graph renders
- health/reset/gc actions work

### `/mes`

- project list renders
- selecting a project loads detail
- stage buttons render correctly
- gate check renders report
- mode A/B/C launch still works
- DAG launch still works
- load compiled subsystem still works

### `/signals`

- catalog renders
- live feed renders
- filter/search/pause/clear work

Use this list as the frontend contract for every later phase.

## Phase 1: Delete The Synthetic Tool Boundary

This is the highest-value first cut.

Current mistake:

- tool exposure is modeled as fake business resources in `lib/ichor/tools`

Files targeted:

- [`lib/ichor/tools.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools.ex)
- [`lib/ichor/tools/runtime_ops.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/runtime_ops.ex)
- [`lib/ichor/tools/project_execution.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/project_execution.ex)
- [`lib/ichor/tools/genesis.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/genesis.ex)
- [`lib/ichor/tools/agent_memory.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/agent_memory.ex)
- [`lib/ichor/tools/profiles.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/profiles.ex)
- [`lib/ichor/tools/archon/memory.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tools/archon/memory.ex)

### Goal

Move `tools do` definitions onto the real owning domains and convert surviving logic into:

- resource actions on real resources
- domain actions
- plain runtime/support modules

### Sequence

1. Create domain-local tool definitions on the owning domains.
2. Point `Archon.Chat` at domain tools instead of tool-wrapper resources.
3. Inline or relocate the surviving action implementations.
4. Delete the wrapper modules.

### Frontend acceptance

- Archon still responds
- fleet controls still work
- MES actions still work
- pipeline/job actions still work
- no visible dashboard regression

### Hard rule

At the end of this phase, `lib/ichor/tools` should be deleted or nearly empty.

## Phase 2: Fix Workshop Modeling

This is the fastest way to make the design reveal itself.

Current mistake:

- `blueprint` is the frontend name, but the durable backend model is `team`
- its internals are stored as anonymous raw maps
- a large pure-state module exists only to compensate for that

Files targeted:

- [`lib/ichor/control/blueprint.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/control/blueprint.ex)
- [`lib/ichor/control/blueprint_state.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/control/blueprint_state.ex)
- [`lib/ichor/control/agent_type.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/control/agent_type.ex)
- [`lib/ichor_web/live/dashboard_workshop_handlers.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_workshop_handlers.ex)
- [`lib/ichor_web/live/workshop_persistence.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_persistence.ex)
- [`lib/ichor_web/live/workshop_types.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/workshop_types.ex)

### Goal

Converge on the durable backend model:

- team
- team member
- agent type

Replace nested arrays of maps with embedded resources:

- agent draft
- spawn link
- communication rule
- tool availability / tool profile

### Sequence

1. Decide whether team members are real child resources or embedded resources.
2. Move the current blueprint persistence shape toward the real team model.
3. Teach the team model to own validation and per-team tool scope.
4. Move prompt building and teammate communication injection into the spawn path.
5. Introduce a single public spawn surface: `spawn_team(name)`.
6. Shrink LiveView state handling to UI state, not data modeling.
7. Delete `BlueprintState` once the persistence and validation logic lives in Ash.

### Frontend acceptance

- Workshop canvas still behaves exactly the same
- existing blueprints load correctly or migrate cleanly
- save/update/delete still work
- launch still works through `spawn_team/1`
- spawned agents receive teammate/MCP/tmux communication context
- spawned agents receive agent-type defaults plus per-team-member instruction overrides
- team-specific tool availability is respected

### Hard rule

If `BlueprintState` still exists at the end, the phase is not done.

## Phase 3: Rebuild Dashboard Reads Around Domains

Current mistake:

- dashboard code directly assembles screens from many resource/runtime calls
- preparation modules paper over missing public reads

Files targeted:

- [`lib/ichor_web/live/dashboard_state.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_state.ex)
- [`lib/ichor/control/views/preparations/load_agents.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/control/views/preparations/load_agents.ex)
- [`lib/ichor/control/views/preparations/load_teams.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/control/views/preparations/load_teams.ex)
- [`lib/ichor/observability/preparations/event_buffer_reader.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/observability/preparations/event_buffer_reader.ex)
- [`lib/ichor/observability/preparations/load_errors.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/observability/preparations/load_errors.ex)
- [`lib/ichor/observability/preparations/load_messages.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/observability/preparations/load_messages.ex)
- [`lib/ichor/observability/preparations/load_tasks.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/observability/preparations/load_tasks.ex)

### Goal

The dashboard should call a small number of page-shaped domain reads.

Not:

- one resource per widget
- one prep module per display projection

### Sequence

1. Define the read shapes needed for `/fleet`, `/pipeline`, `/mes`, and `/signals`.
2. Implement them as explicit domain reads/projections.
3. Replace LiveView scatter-gather calls.
4. Delete the preparation modules.

### Frontend acceptance

- all five pages still render correctly
- filters, counts, grouped data, and status bars still match
- no stale/missing panels

### Hard rule

If the dashboard still depends on preparation modules for core data, this phase is not done.

## Phase 4: Break Apart The Factory God Modules

Current mistake:

- project execution logic is concentrated in giant orchestration modules

Files targeted:

- [`lib/ichor/projects/runtime.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/runtime.ex)
- [`lib/ichor/projects/runner.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/runner.ex)
- [`lib/ichor/projects/spawn.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/spawn.ex)
- [`lib/ichor/projects/team_spec.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/team_spec.ex)
- [`lib/ichor/projects/team_prompts.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/team_prompts.ex)
- [`lib/ichor/projects/mode_prompts.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/mode_prompts.ex)
- [`lib/ichor/projects/dag_prompts.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/dag_prompts.ex)

### Goal

Separate:

- runtime processes
- prompt library
- build/spec assembly
- domain actions

Also unify team spawning semantics across planning and execution:

- `spawn_team("mes")`
- `spawn_team("mode-a")`
- `spawn_team("mode-b")`
- `spawn_team("mode-c")`

### Sequence

1. Pull prompt text into one prompt library area.
2. Move stable business operations into domain actions.
3. Keep only real OTP lifecycle inside runtime modules.
4. Delete `projects/spawn.ex` by redistributing its responsibilities.

### Frontend acceptance

- mode launches still work
- DAG launches still work
- run status still updates
- scheduler-driven MES behavior still works
- the frontend can trigger team spawns through one consistent spawn API

### Hard rule

No single module should remain as the default place to put "whatever else the project flow needs".

## Phase 5: Decide The Real Shape Of Planning Artifacts

Current mistake:

- too much concept variance is hidden behind `kind`
- task ownership is still blurred between app state and file sync
- the MES project may be split into `project` and `node` even though `genesis`/`node` is only a pet name

Files targeted:

- [`lib/ichor/projects/artifact.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/artifact.ex)
- [`lib/ichor/projects/roadmap_item.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/roadmap_item.ex)
- [`lib/ichor/projects/pipeline_stage.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/pipeline_stage.ex)
- [`lib/ichor/tasks/board.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tasks/board.ex)
- [`lib/ichor/tasks/jsonl_store.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/tasks/jsonl_store.ex)
- any remaining callers that branch on `kind`

### Goal

Decide which concepts are truly separate resources and which can stay unified.

Also make task ownership explicit:

- tasks are app/database-owned
- DAG shape is derived from tasks
- `tasks.jsonl` is an external sync target for repo-local workflows

Also decide whether the current MES `project` and `node` split should collapse into one resource.

Do not split by aesthetics. Split only where the rules are actually different.

### Decision rule

Split when there are distinct:

- validations
- relationships
- lifecycle actions
- query surfaces
- user flows

Keep unified when the differences are mostly presentational.

### Likely outcome

- `Artifact` probably needs to split more than it is now
- `RoadmapItem` may be allowed to stay partially unified

### Frontend acceptance

- MES artifact tabs still work
- artifact reader still works
- roadmap reader still works
- pipeline launch/generation still works
- tasks shown in `/pipeline` still match repo-local `tasks.jsonl` where applicable

## Phase 6: Rationalize Signals And Notifiers

Current mistake:

- one global custom notifier table is becoming the integration point for everything

Files targeted:

- [`lib/ichor/signals/from_ash.ex`](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/from_ash.ex)
- resources currently using `simple_notifiers: [Ichor.Signals.FromAsh]`

### Goal

Use the lightest notifier that matches the actual need.

### Sequence

1. Keep custom signal emission only where the catalog demands custom mapping.
2. Use `Ash.Notifier.PubSub` where direct publication is enough.
3. Keep ownership-local publication logic close to the owning resources.

### Frontend acceptance

- `/signals` still shows the same important events
- `/fleet`, `/pipeline`, and `/mes` still receive live updates

## Phase 7: Final Naming Pass

Only do this after the previous phases.

At this point the design should have revealed:

- which concepts are real
- which ones stayed embedded
- which ones were only actions
- which ones were only runtime modules

Then rename modules to match the revealed model.

Not before.

## Recommended Working Order

If you are tired and want the maximum clarity fast, do exactly this order:

1. Phase 1: delete the synthetic `tools/` boundary
2. Phase 2: fix Workshop with embedded resources
3. Phase 3: replace dashboard preparation shims with domain reads
4. Phase 4: break apart project-execution god modules
5. Phase 5: decide artifact/resource splits
6. Phase 6: rationalize signal notifiers
7. Phase 7: final naming pass

## Definition Of Done

The refactor is done when:

- the frontend still behaves the same
- the synthetic `tools/` boundary is gone
- Workshop nested data is modeled in Ash, not raw maps
- preparation shims are gone
- the big orchestration dumping-ground modules are broken apart
- every remaining named module clearly earns its name
