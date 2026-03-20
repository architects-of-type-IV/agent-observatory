# MES Page

## Overview

The MES page is the Factory view for project intake, planning, and pipeline launch.
It is rendered inside `DashboardLive` when `?view=mes` and is backed by the
`Ichor.Factory` domain, not the old `Projects/Genesis/DAG` split.

The current nouns are:

- `Project` = durable MES project
- `Artifact` = embedded planning document inside a project
- `RoadmapItem` = embedded planning tree item inside a project
- `Pipeline` = executable delivery projection
- `PipelineTask` = executable task unit inside a pipeline

## Layout

The page has three working areas when a project is selected:

- left: project feed
- center: planning and gate flow
- right: project metadata

When nothing is selected, only the project feed is shown.

## Header

The header shows:

- title: `Manufacturing Execution System`
- subtitle: `Subsystem Production Line`
- MES scheduler status
- pause/resume button

The scheduler is driven by `Ichor.Factory.MesScheduler`. The UI event is
`toggle_mes_scheduler`, handled in
[/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_mes_handlers.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_mes_handlers.ex).

The status map comes from `MesScheduler.status/0` and currently includes:

- `tick`
- `active_runs`
- `next_tick_in`
- `paused`

## Project Feed

The left column lists MES projects from `Ichor.Factory.Project.list_all!/0`.

Each row shows:

- plugin/module name
- title
- topic
- version
- status

Clicking a row fires `mes_select_project`. That loads:

- `selected_mes_project` for metadata
- `planning_project` for the planning detail panel

The detail side intentionally reads the current `Project` record again, because
the planning panel depends on embedded `artifacts` and `roadmap_items`.

## Center Panel

The center column is the planning and build surface.

### Action bar

The action bar is rendered by
[/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_factory_components.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_factory_components.ex).

It shows:

- current project title
- derived project stage via `Ichor.Factory.ProjectStage`
- mode buttons `A`, `B`, `C`
- gate button
- build button

Current major events:

- `mes_start_mode`
- `mes_gate_check`
- `mes_generate_dag`
- `mes_launch_dag`
- `mes_deselect_project`

### Planning teams

`mes_start_mode` no longer launches a `genesis` team. It launches a planning team:

- `Spawn.ensure_planning_project/2`
- `Spawn.spawn(:planning, mode, project_id, planning_project_id)`

The run-team spec is currently built by
[/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex)
using the `:planning` path.

### Gate report

`mes_gate_check` calls `Ichor.Factory.Project.gate_check/1`.

The gate report is now Factory-owned. The LiveView only normalizes the returned
map for display. The gate report tracks planning readiness from embedded project
content, including:

- ADR count
- accepted ADR count
- feature count
- use case count
- checkpoint count
- phase count
- readiness booleans for define/build/complete

### Planning artifacts

The tabbed artifact browser now uses planning terminology:

- `planning_switch_tab`
- `planning_select_artifact`
- `planning_close_reader`

Tabs are:

- `decisions`
- `requirements`
- `checkpoints`
- `roadmap`

The content comes from embedded project data:

- artifacts of kind `:adr`, `:feature`, `:use_case`, `:checkpoint`, `:conversation`
- roadmap items of kind `:phase`

The reader and list components live in:

- [/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_artifact_components.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_artifact_components.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_reader_components.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_reader_components.ex)

### Pipeline generation and launch

The UI still uses the historical event name `mes_generate_dag`, but the behavior
is now pipeline-oriented:

- `PipelineCompiler.generate(project_id)`
- `PipelineCompiler.to_jsonl_string(tasks)`
- append to `tasks.jsonl`
- emit `:mes_pipeline_generated`

`mes_launch_dag` likewise launches a pipeline team:

- `Spawn.spawn(:pipeline, project_id, project_id)`
- emit `:mes_pipeline_launched`

The event names are still transitional, but the domain model is already
`Pipeline` and `PipelineTask`.

## Right Sidebar

The metadata sidebar is rendered by
[/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_detail_components.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_detail_components.ex).

It displays project-owned fields such as:

- title
- description
- plugin
- output kind
- topic
- version
- signal interface
- features
- use cases
- architecture
- dependencies
- emitted/subscribed signals

`Project.output_kind` is important now. MES currently defaults to `plugin`, but
completion no longer assumes every project result must be a plugin forever.

## Status Actions

Project status actions are rendered by
[/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_status_components.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_status_components.ex).

Current actions:

- `mes_pick_up`
- `mes_load_plugin`

The load action calls `Ichor.Factory.PluginLoader.compile_and_load/1`.

## Signals

MES signals are rendered by
[/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/mes.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/mes.ex).

Important current MES signal families:

- project lifecycle: `mes_project_created`, `mes_project_picked_up`
- planning/pipeline launch: `planning_team_ready`, `mes_pipeline_generated`, `mes_pipeline_launched`
- scheduler: `mes_scheduler_init`, `mes_scheduler_paused`, `mes_scheduler_resumed`, `mes_tick`
- runtime: `mes_run_init`, `mes_run_started`, `mes_run_terminated`
- maintenance: `mes_maintenance_init`, `mes_maintenance_cleaned`, `mes_maintenance_error`
- plugin output: `mes_plugin_loaded`, `mes_plugin_compile_failed`, `mes_output_unhandled`

## Key Files

- [/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_mes_handlers.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_mes_handlers.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_components.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_components.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_factory_components.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_factory_components.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/project.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/project.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/spawn.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/spawn.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/pipeline_compiler.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/pipeline_compiler.ex)
- [/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/mes_scheduler.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/mes_scheduler.ex)
