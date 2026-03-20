Let me search for the MES page components and handlers.
Now let me check the `PipelineStage` module used in the action bar, and look at the `mes_events` list and any remaining handler details.
I now have a complete picture of the MES page. Here is the comprehensive feature description:

---

# MES Page -- Complete Feature Description

## Overview

The MES page (Manufacturing Execution System) is a full-page LiveView panel accessible via the `/mes` route. It is one of five top-level navigation views in the Ichor dashboard. Its purpose is to track and operate the lifecycle of AI-built subsystem projects, from initial ideation through multi-mode planning (Genesis pipeline), DAG-based code generation, compilation, and runtime loading into the BEAM.

---

## Layout Structure

The page uses a three-column layout when a project is selected, collapsing to a single-column list view when nothing is selected.

- **Header bar** (always visible): page title ("Manufacturing Execution System"), subtitle ("Subsystem Production Line"), scheduler status indicator, and scheduler pause/resume toggle.
- **Left column** -- Project Feed (always visible): scrollable list of all MES projects. Narrows to compact mode when a project is selected.
- **Center column** -- Factory Detail (visible when a project is selected): action bar, optional gate report, artifact tabs and reader.
- **Right column** -- Metadata Sidebar (visible when a project is selected): static project metadata.

---

## Header Bar

**UI elements:**
- Title: "Manufacturing Execution System"
- Subtitle: "Subsystem Production Line"
- Scheduler status pill: shows current tick number (monospaced), active run count OR "Paused" label, animated green dot (running) or amber dot (paused).
- Pause/Resume button: toggles `Ichor.Projects.Scheduler`. "Pause" in amber when running, "Resume" in brand color when paused.

**Interactions:**
- `phx-click="toggle_mes_scheduler"` -- calls `Scheduler.pause()` or `Scheduler.resume()` depending on current state, then re-fetches scheduler status.

**Data source:** `Ichor.Projects.Scheduler.status/0` returns `%{tick, active_runs, next_tick_in, paused}`.

---

## Project Feed (Left Column)

**UI elements:**
- Empty state: message "No projects yet. The scheduler will spawn the first team shortly."
- Sticky column header: Module / Project / Topic / Ver / Status (Topic and Ver hidden in compact mode).
- Project rows (one per project), clickable.

**Per-row data displayed:**
- Subsystem module name (last segment only, monospaced, brand color) -- e.g., `AuthCore`
- Project title (bold)
- Topic (monospaced, muted) -- hidden in compact mode
- Version (monospaced, centered) -- hidden in compact mode
- Status badge (right-aligned)

**Status badges:**
- `:proposed` -- "Proposed" (info color)
- `:in_progress` -- "Building" (brand color)
- `:compiled` -- "Compiled" (success color)
- `:loaded` -- "Live" with animated pulse dot (success color)
- `:failed` -- "Failed" (error color)
- Any other atom -- displayed as-is (muted)

**Interactions:**
- `phx-click="mes_select_project"` with `phx-value-id` -- selects a project, loads its Genesis node (with all associations), switches layout to 3-column.
- Selected row is highlighted with a brand-colored left border.

**Data source:** `Ichor.Projects.Project.list_all!/0` -- called on initial navigation to `:mes` and after any project mutation.

---

## Action Bar (Center Column Top, when project selected)

**UI elements:**
- Project title (bold, truncated)
- "Back to list" button -- deselects the current project, clears genesis_node, gate_report, genesis_selected.
- Pipeline stage badge -- color-coded label for the current stage (see Pipeline Stage section below).
- Station buttons: **A**, **B**, **C**, **Gate**, **Build** -- each visually reflects its state (active/completed/future).

**Station button behavior:**
- Mode buttons (A/B/C): active = clickable brand style; completed = clickable success style; future = non-clickable muted.
- Gate button: active = clickable brand style; completed = non-clickable success style; future = non-clickable muted.
- Build button: active = clickable amber style labeled "Build"; completed = non-clickable success style labeled "Built"; future = non-clickable muted.

**Interactions:**
- `phx-click="mes_start_mode"` with `phx-value-mode` (a/b/c) and `phx-value-project-id` -- spawns a Genesis team in the given mode via `Ichor.Projects.Spawn.spawn(:genesis, mode, project_id, node_id)`. Ensures a Genesis node exists first. Shows flash on success or error.
- `phx-click="mes_gate_check"` with `phx-value-node-id` -- runs a gate readiness check and stores the report in `gate_report` assign. Triggers display of the Gate Report panel.
- `phx-click="mes_launch_dag"` with `phx-value-node-id` and `phx-value-project-id` -- launches a DAG build team via `Spawn.spawn(:dag, node_id, project_id)`. Emits `:mes_dag_launched` signal on success.
- `phx-click="mes_deselect_project"` -- clears `selected_mes_project`, `genesis_node`, `genesis_selected`, `gate_report`.

---

## Pipeline Stage System

`Ichor.Projects.PipelineStage.derive/1` computes the current stage from loaded Genesis node associations. Stages in order:

| Stage | Label | Color |
|---|---|---|
| `:ideation` | Ideation | brand |
| `:mode_a` | Mode A | brand |
| `:pre_gate_a` | Pre-Gate A | brand |
| `:mode_b` | Mode B | interactive |
| `:pre_gate_b` | Pre-Gate B | interactive |
| `:mode_c` | Mode C | interactive |
| `:pre_gate_c` | Pre-Gate C | warning |
| `:ready_for_dag` | Ready for DAG | warning |
| `:building` | Building | warning |
| `:compiled` | Compiled | success |
| `:running` | Running | success |

Stage is derived from what artifacts exist on the node (ADRs -> features/use_cases -> phases) and which gate checkpoints have been recorded. If an active DAG run exists for the node (`Run.by_node!/1` non-empty), stage is forced to `:building`.

Station states (active/completed/future) for each Mode button and the Gate/Build buttons are fully deterministic from the stage -- defined by `station_states/1` clause matching.

---

## Gate Report Panel (Center Column, conditional)

Appears below the action bar when `mes_gate_check` is fired. Dismisses on deselect.

**UI elements:**
- Header: "Gate Readiness Report" + current node status (monospaced)
- 2-column metric grid: ADRs, Accepted ADRs, Features, Use Cases, Checkpoints, Phases (each as a label/value pair)
- Verdict rows:
  - "Ready for Define" -- green dot + success text if `adrs > 0 and accepted_adrs > 0`, otherwise error dot + muted text
  - "Ready for Build" -- green if `features > 0 and use_cases > 0`
  - "Ready for Complete" -- green if `phases > 0`

**Data source:** Built by `build_gate_report/1` in `DashboardMesHandlers` from the loaded genesis node's associations.

---

## Artifact Tabs (Center Column, when Genesis node exists)

Four tabs, each showing a count badge:

- **Decisions** -- count of ADRs
- **Requirements** -- count of features + use_cases
- **Checkpoints** -- count of checkpoints + conversations
- **Roadmap** -- count of phases

**Interaction:** `phx-click="genesis_switch_tab"` with `phx-value-tab` -- switches `genesis_sub_tab` assign and clears `genesis_selected`.

---

## Artifact List (Center Column, below tabs)

Shown when no artifact is selected (`genesis_selected` is nil). Renders a list of items for the active tab.

**Per-item display:**
- Code label (monospaced, colored): ADRs get brand color, Features/Use Cases get interactive color, Phases get success color
- Title (bold, truncated)
- Badge: ADR status, checkpoint/conversation mode, or empty

**Interactions:** `phx-click="genesis_select_artifact"` with `phx-value-type` and `phx-value-id` -- sets `genesis_selected` to `{type, id}` tuple, triggering reader sidebar.

**Tab contents:**
- Decisions: all ADRs (code, title, status badge)
- Requirements: all Features (code, title) + all Use Cases (code, title), concatenated
- Checkpoints: all Checkpoints (title, mode badge) + all Conversations (title, mode badge)
- Roadmap: all Phases (P{number}, title)

---

## Reader Sidebar (Center Column, replaces artifact list when artifact selected)

Shown when `genesis_selected` is set. Replaces the artifact list.

**UI elements:**
- Code label (bold, brand monospaced) + status/mode badge
- Close button -- `phx-click="genesis_close_reader"` -- clears `genesis_selected`
- Title (large, bold)
- Cross-reference chips: clickable tags for related ADRs, parent features, or governing ADRs -- each `phx-click="genesis_select_artifact"` navigates to that artifact
- Content area: markdown rendered to HTML via Earmark

**Content per artifact type:**
- ADR: `content` field, cross-refs to related ADR codes
- Feature: `content` field, cross-refs to referenced ADR codes
- Use Case: `content` field, cross-ref to parent feature code
- Checkpoint / Conversation: `content` field, no cross-refs
- Phase: structured HTML rendering via `MesPhaseRenderer`

**Phase reader (MesPhaseRenderer):**
- Stats bar: section count, task count, subtask count
- Goals list (bulleted)
- Section cards: each shows section number badge, title, goal (italic), task rows
- Task rows: colored status dot (pending/in-progress/completed), task number + title, governed-by ADR codes, parent UC code, nested subtask rows
- Subtask rows: colored status dot, number + title, blocked-by task IDs, goal text

---

## Metadata Sidebar (Right Column, ~400px, when project selected)

**UI elements and data displayed:**
- Project title and subsystem module name (monospaced)
- Description text
- Features list (what it does) -- bordered left with zinc line
- Use Cases list (what it solves) -- bordered left with brand color
- Signals Emitted -- tag list (monospaced chips)
- Signals Subscribed -- tag list (monospaced chips)
- Architecture -- monospace preformatted block
- Dependencies -- tag list
- Footer: version, topic (monospaced), signal_interface

**Data source:** Project struct fields from `Ichor.Projects.Project`.

---

## Status-Driven Action Buttons (in MesStatusComponents)

These buttons appear in the project list or detail context depending on status:
- `:proposed` -- "Pick Up" button: `phx-click="mes_pick_up"` -- calls `Project.pick_up(project, "manual")`, emits `:mes_project_picked_up` signal, refreshes project list.
- `:compiled` -- "Load into BEAM" button: `phx-click="mes_load_subsystem"` -- calls `SubsystemLoader.compile_and_load(project)`, marks project loaded or failed, refreshes project list.

---

## "Generate DAG" Feature

Accessible from `MesGenesisComponents.genesis_panel` (the older genesis panel component, used in contexts other than the main factory view). When a Genesis node exists:
- `phx-click="mes_generate_dag"` with `phx-value-node-id` -- calls `DagGenerator.generate(node_id)`, converts result to JSONL, appends to `tasks.jsonl` in the cwd, emits `:mes_dag_generated` signal.
- Flash: "No subtasks found -- run Mode C first" if empty; "DAG generated: N tasks appended to tasks.jsonl" on success.

---

## All Events Handled by MES

Registered in `@mes_events` in `DashboardLive`:

| Event | Action |
|---|---|
| `mes_pick_up` | Picks up a proposed project, marks in-progress |
| `mes_load_subsystem` | Compiles and hot-loads subsystem into BEAM |
| `toggle_mes_scheduler` | Pauses or resumes the MES scheduler |
| `mes_select_project` | Selects a project, loads genesis node |
| `mes_deselect_project` | Clears selection and all detail state |
| `mes_start_mode` | Spawns a Genesis team in mode A, B, or C |
| `mes_gate_check` | Runs gate readiness report |
| `mes_generate_dag` | Generates DAG tasks from planning artifacts, appends to tasks.jsonl |
| `mes_launch_dag` | Launches DAG build team (spawns a DAG-mode team) |
| `genesis_switch_tab` | Switches artifact tab (decisions/requirements/checkpoints/roadmap) |
| `genesis_select_artifact` | Opens artifact reader for a specific item |
| `genesis_close_reader` | Closes artifact reader |

---

## State Initialized on Navigation to `:mes`

Set by `apply_nav_view(:mes, socket)` in `DashboardLive`:
- `mes_projects` -- full project list from `Project.list_all!/0`
- `mes_scheduler_status` -- scheduler status map (tick, active_runs, next_tick_in, paused)
- `selected_mes_project` -- nil
- `genesis_node` -- nil
- `gate_report` -- nil

Default assigns (from `default_assigns/1`): also `genesis_sub_tab: :decisions`, `genesis_selected: nil`.

---

## Signal Feed Integration

MES signals are rendered in the Signals view feed (`IchorWeb.SignalFeed.Renderers.Mes`). All MES domain signals with dedicated renderers:

- Project lifecycle: `mes_project_created`, `mes_project_picked_up`, `mes_project_compiled`, `mes_project_failed`
- Subsystem loading: `mes_subsystem_loaded`, `mes_subsystem_compile_failed`
- Scheduler: `mes_scheduler_init`, `mes_scheduler_paused`, `mes_scheduler_resumed`, `mes_tick`, `mes_cycle_started`, `mes_cycle_skipped`, `mes_cycle_failed`, `mes_cycle_timeout`
- Team lifecycle: `mes_team_ready`, `mes_team_killed`, `mes_team_spawn_failed`
- Agent lifecycle: `mes_agent_registered`, `mes_agent_stopped`, `mes_agent_tmux_gone`, `mes_agent_register_failed`
- Run lifecycle: `mes_run_init`, `mes_run_started`, `mes_run_terminated`
- Quality gates: `mes_quality_gate_passed`, `mes_quality_gate_failed`, `mes_quality_gate_escalated`
- DAG: `mes_dag_generated`, `mes_dag_launched`
- Tmux spawning: `mes_tmux_spawning`, `mes_tmux_session_created`, `mes_tmux_spawn_failed`, `mes_tmux_window_created`
- Research: `mes_research_ingested`, `mes_research_ingest_failed`
- Housekeeping: `mes_janitor_init`, `mes_janitor_cleaned`, `mes_janitor_error`, `mes_prompts_written`, `mes_operator_ensured`, `mes_cleanup`, `mes_run_init`

---

## Research Facility (DashboardMesResearchHandlers)

A secondary handler module exists for a Research Facility feature. It handles:
- `mes_research_search` -- searches `ResearchStore` by query, stores results in `mes_research_results`
- `mes_select_research_entity` -- selects an entity from `mes_research_entities`
- `mes_select_research_episode` -- selects an episode from `mes_research_episodes`
- `mes_research_refresh` -- reloads entities and episodes from `ResearchStore`

These events are NOT in the current `@mes_events` list in `DashboardLive`, and no Research Facility UI is present in the current template. This handler exists but is not wired into the live view routing or rendered in any heex. It is a dormant or in-progress feature.

---

## Key Files

- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_live.ex` -- event routing, nav view initialization
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_mes_handlers.ex` -- all active MES event handlers
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_mes_research_handlers.ex` -- dormant Research Facility handlers
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/live/dashboard_state.ex` -- default assigns and recompute
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_components.ex` -- top-level layout orchestrator
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_feed_components.ex` -- project list table
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_factory_components.ex` -- action bar, mode/gate/build buttons, tab bar
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_artifact_components.ex` -- artifact list per tab
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_reader_components.ex` -- artifact reader sidebar with cross-references
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_phase_renderer.ex` -- phase hierarchy HTML renderer
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_gate_components.ex` -- gate readiness report panel
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_detail_components.ex` -- right-side metadata sidebar
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_status_components.ex` -- status badges and action buttons
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/mes_genesis_components.ex` -- genesis panel (older component with mode buttons, artifact summary counts, gate check, generate DAG)
- `/Users/xander/code/www/kardashev/observatory/lib/ichor/projects/pipeline_stage.ex` -- stage derivation and station state logic
- `/Users/xander/code/www/kardashev/observatory/lib/ichor_web/components/signal_feed/renderers/mes.ex` -- signal feed renderers for all MES domain signals
