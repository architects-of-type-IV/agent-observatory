# MES Unified Factory View Design

**Date:** 2026-03-17 | **Status:** IMPLEMENTED

## Core Concept

MES is the facility -- an automated factory where each project is a product moving through the production line from ideation to running code. The view shows pipeline position (derived from artifacts), all stations (action buttons), and the artifacts produced at each stage.

Pipeline: Ideation -> Mode A (ADRs) -> Gate A -> Mode B (FRDs/UCs) -> Gate B -> Mode C (Roadmap) -> Gate C -> DAG -> Running

**Pipeline stage is derived, not stored.** A pure function (`Ichor.Genesis.PipelineStage.derive/1`) examines the genesis node's loaded associations to determine the current stage. No schema change needed.

## Layout

```
+--------+--------------------------------------------+------------------+
| Feed   | Main Content                               | Metadata Sidebar |
| (proj  |                                            | (signals, arch,  |
|  list) | Action Bar: [title] [stage] [Mode A/B/C]   |  deps, pipeline) |
|        |            [Gate] [DAG]                     |                  |
|        +--------------------------------------------+                  |
|        | Project description                        |                  |
|        +--------------------------------------------+                  |
|        | [Decisions] [Requirements] [Checkpoints]   |                  |
|        |                [Roadmap]                    |                  |
|        +--------------------------------------------+                  |
|        | Artifact list (per active tab)              |                  |
|        | - ADR-001: Title [accepted]                 |                  |
|        | - ADR-002: Title [accepted]                 |                  |
|        |                                            |                  |
+--------+--------------------------------------------+------------------+
                           |
                     click artifact
                           |
                           v
+--------+--------------------------------------------+------------------+
| Feed   | Artifact list    | Reader Sidebar          | Metadata Sidebar |
|        | (compressed)     | [Close]                 |                  |
|        |                  | ADR-001                 |                  |
|        |  ADR-001 *       | Status: accepted        |                  |
|        |  ADR-002         |                         |                  |
|        |  ADR-003         | References:             |                  |
|        |                  |  [ADR-002] [FRD-001]    |                  |
|        |                  |                         |                  |
|        |                  | ## Context              |                  |
|        |                  | The Pulse Monitor...    |                  |
|        |                  |                         |                  |
|        |                  | ## Decision             |                  |
|        |                  | Use SQLite via...       |                  |
+--------+------------------+-------------------------+------------------+
```

## Components

### Feed (left, existing)
MES project list. No changes except: show a planning indicator on projects that have a genesis node.

### Action Bar (top of main content)
- Project title + subsystem module name
- Pipeline stage badge (discover / define / build / complete / "no plan")
- Compact artifact counts inline (3 ADR, 1 FRD, 1 UC, 0 Phase)
- Action buttons: Mode A, Mode B, Mode C, Gate Check, Generate DAG
- Mode buttons should be contextual: Mode A highlighted when in discover stage, etc.

### Artifact Tabs (below description)
Four tabs organizing artifacts by type, matching the Genesis vault pattern:

**Decisions** -- ADRs. List shows code, title, status badge. Each ADR has: related_adr_codes (clickable links to other ADRs).

**Requirements** -- Features (FRDs) and Use Cases. Features show: code, title, content, adr_codes (links to ADRs). Use Cases show: code, title, content, feature_code (link to feature).

**Checkpoints** -- Gate assessments and conversations. Checkpoints show: title, mode, summary, content. Conversations show: title, mode, content (transcript).

**Roadmap** -- Phases > Sections > Tasks > Subtasks. This is the only truly hierarchical view. Phases list with nested sections/tasks. This tab also has the "Generate DAG" action.

### Reader Sidebar (appears on artifact click)
Slides in between main content and metadata sidebar. Shows:
- Artifact code + status badge
- Title
- Cross-references: "References" (what this points to) and "Referenced by" (what points to this). All clickable -- clicking navigates to that artifact.
- Full rendered markdown content (Earmark)
- Close button to dismiss

Cross-references are resolved from database relationships:
- ADR.related_adr_codes -> other ADRs
- Feature.adr_codes -> ADRs
- UseCase.feature_code -> Feature
- Phase.governed_by -> ADR/FRD codes
- Task.governed_by -> FRD codes
- Task.parent_uc -> UC code
- Subtask.blocked_by -> other subtask UUIDs

### Metadata Sidebar (right, always visible)
Compact, non-interactive reference info:
- Pipeline metrics (key-value rows, not big number boxes)
- Signals emitted (tags)
- Signals subscribed (tags)
- PubSub topic
- Architecture (mono block)
- Dependencies (tags)

## Data Flow

### Assigns
- `@mes_projects` -- existing
- `@selected_mes_project` -- existing
- `@genesis_node` -- loaded with all associations when project selected
- `@genesis_sub_tab` -- :decisions / :requirements / :checkpoints / :roadmap
- `@genesis_selected` -- nil or {type_atom, id} for reader sidebar

### Events
- `mes_select_project` -- loads project + genesis node (existing, extend to load node)
- `genesis_switch_tab` -- switches artifact tab
- `genesis_select_artifact` -- opens reader sidebar
- `mes_start_mode` -- launches Mode A/B/C team (existing)
- `mes_gate_check` -- runs gate validation (existing)
- `mes_generate_dag` -- generates tasks.jsonl (existing)

### LiveView Updates
Subscribe to genesis signals. When agents create artifacts (ADRs, checkpoints), reload the genesis node so the list updates live.

## Implementation (2026-03-17)

### New Files
- `lib/ichor/genesis/pipeline_stage.ex` -- Pure pipeline stage derivation + station states + color mapping
- `lib/ichor_web/components/mes_factory_components.ex` -- Action bar, description, tab bar, artifact list
- `lib/ichor_web/components/mes_artifact_components.ex` -- Reader sidebar with cross-refs and markdown

### Modified Files
- `lib/ichor_web/components/mes_components.ex` -- Rewritten: unified layout, no tabs
- `lib/ichor_web/components/mes_detail_components.ex` -- Converted to metadata sidebar
- `lib/ichor_web/live/dashboard_mes_handlers.ex` -- Removed tab/node-list handlers, added close_reader
- `lib/ichor_web/live/dashboard_state.ex` -- Removed tab/research assigns
- `lib/ichor_web/live/dashboard_live.html.heex` -- Simplified MES view props

### Dead Code (no longer imported)
- `genesis_tab_components.ex` -- replaced by factory + artifact components
- `mes_research_components.ex` -- research tab removed from unified view
