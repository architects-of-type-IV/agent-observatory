# Factory Domain
Related: [Index](INDEX.md) | [Workshop Domain](workshop-domain.md) | [Signals Domain](signals-domain.md) | [Diagrams](../diagrams/architecture.md)

Factory owns: project lifecycle, pipeline/task tracking, run orchestration, external file interop.
Factory does NOT own: team compilation (delegates to Workshop.TeamSpec), Board mutation on agent crash (should subscribe to `:agent_crashed` signal).

---

## Purpose

The `/mes` page is a control panel. Every button either spawns a team or produces artifacts for a future spawn:

| Button | What It Does |
|--------|-------------|
| Resume / Pause | `spawn("mes")` or MesScheduler queue drain |
| Mode A / B / C | `spawn("planning-a/b/c")` -- planning team produces ADRs/FRDs/roadmap |
| Gate Check | No spawn -- validates gate readiness |
| Generate DAG | No spawn -- generates `tasks.jsonl` from roadmap |
| Build | `spawn("pipeline")` -- build team executes tasks from roadmap |

---

## Ash Resources

### Project (`projects`)

Durable record for a planning brief being turned into requirements.

**Key fields**: `title`, `description`, `stakeholders[]`, `planning_stage` (discover/define/build/complete), `status` (proposed/in_progress/compiled/loaded/failed), `team_name`, `run_id`, `artifacts[]` (embedded), `roadmap_items[]` (embedded).

**Authority**: AshSqlite. Canonical source for project state.

### Pipeline (`pipelines`)

A single build execution attempt. Groups PipelineTasks into a run.

**Key fields**: `label`, `source` (project/imported), `project_id`, `tmux_session`, `status` (active/completed/failed/archived).

**Note**: `project_id` is a plain text field (no FK) -- pipelines can be imported from external projects.

### PipelineTask (`pipeline_tasks`)

An executable task unit within a pipeline. One line in `tasks.jsonl` mirrored as an Ash resource.

**Key fields**: `run_id` (FK to Pipeline), `external_id`, `subject`, `description`, `goal`, `blocked_by[]`, `status` (pending/in_progress/completed/failed), `owner`, `priority`, `wave`, `acceptance_criteria[]`, `claimed_at`, `completed_at`.

**Authority**: AshSqlite. Canonical source for task status for runs WE created. For external projects, `tasks.jsonl` is the interop source (see PipelineMonitor below).

---

## Modules

### Factory.Floor

Ash action surface for Factory operator/control actions. Provides the code interface called by the MES LiveView handlers.

**Issue (W4, W5-1)**: Returns opaque `:map` with string keys for UI. Should delegate to a view module (`Factory.FloorView`) and return typed structs.

### Factory.Spawn

Planning/pipeline team launch orchestration. Entry point for UC3 and UC4.

**Current**: Calls `TeamSpec.build(:planning | :pipeline, ...)` directly -- mode knowledge is hardcoded here AND in TeamSpec.

**Target**: Does Factory-specific pre-spawn work (load tasks, validate DAG, group workers), then calls `spawn("pipeline")` with context. Mode knowledge stays in the caller (Spawn), not in the compiler (TeamSpec).

Pre-spawn steps for pipeline:
1. `Loader.from_project(project_id)` -- loads Pipeline + PipelineTasks from Ash
2. `Validator.validate_pipeline(tasks)` -- validates the task DAG (no cycles, all deps exist)
3. `WorkerGroups.build(tasks)` -- groups tasks into parallel worker batches by wave/dependency
4. `TeamSpec.compile(canvas_state, prompt_module: PipelinePrompts, context: ctx)`

### Projects.RunManager (target -- current: Factory.Runner)

GenServer per active run. Monitors the run lifecycle, subscribes to signals, manages transitions.

**Keep this GenServer** (AD decision): it holds live run state that cannot be reconstructed on demand. Subscribes to agent lifecycle signals and pipeline task signals.

**Current state (runner.ex:422-437)**: Five functions with three clauses each on `:mes | :pipeline | :planning`. Replace with `RunRef` value object dispatch (AD-7).

### Projects.Query (target -- current: Factory.PipelineMonitor)

**DELETE the GenServer**. Replace with:
- Pure query module reading from `PipelineTask` Ash resource (no process)
- Oban cron workers for health check + project discovery
- Ash notifier broadcasts when pipeline tasks change (replaces 3s poll)
- LiveView subscribes to signals, calls query module directly

PipelineMonitor is 623 lines. It serializes all reads and writes. Runs bash inside `GenServer.call` with a 15s timeout. This violates AD-4 (pure model vs. runtime adapter) and AD-8 (mandatory work through reliable path).

### Factory.MesScheduler -> Oban Cron Worker

**DELETE the GenServer**. Replace with:
- Oban cron worker on `mes` queue, every 60s
- Pause/resume = Oban queue drain/resume (no file-flag mechanism)
- `max_concurrency: 1` on `mes` queue prevents parallel MES runs

---

## Two Data Sources for Tasks (UC7)

The app monitors agents across ALL git projects. This creates a dual-source design:

| Source | Authority | What It Tracks |
|--------|-----------|----------------|
| `PipelineTask` (Ash) | Our system | Tasks we created. Written when agents claim/complete via MCP. |
| `tasks.jsonl` (file) | External projects | Tasks in other git repos. Read-only from our side (interop). |

**Sync path (write-through)**: When our agents update a PipelineTask via Ash, a `FromAsh` notifier calls `Runner.Exporter.sync_task_to_file` to write the change back to `tasks.jsonl`. This keeps external tooling in sync.

**NOT duplication** (S4 from audit): these are two different authorities for two different populations of tasks. PipelineMonitor's job is the external-file adapter. PipelineTask is our internal truth.

---

## Oban Workers

Factory uses Oban for all durable background work. Current workers in `factory/workers/`:

| Worker | Queue | Purpose |
|--------|-------|---------|
| `MesWorker` (planned) | `mes` | Replaces MesScheduler GenServer |
| `HealthCheckWorker` (planned) | `pipeline` | Replaces PipelineMonitor health check bash call |
| `ProjectDiscoveryWorker` (planned) | `pipeline` | Periodic scan for new external projects |
| `CleanupWorker` (planned) | `cleanup` | Idempotent pipeline archive + task reset |

Per AD-8: cleanup work inserts Oban jobs directly from Ash notifiers, not via PubSub subscribers.

---

## Domain Ownership Boundaries

Factory **calls**:
- `Workshop.TeamSpec.compile` (team compilation -- Workshop owns this)
- `Infrastructure.TeamLaunch.launch` (via TeamSpec result)

Factory **emits signals** for:
- `:run_started`, `:run_completed`, `:run_failed`
- `:pipeline_task_claimed`, `:pipeline_task_completed`
- `:project_created`, `:project_updated`

Factory **subscribes to signals** from:
- `:agent_crashed` -- react by reassigning tasks (currently a direct cross-domain call in AgentWatchdog, should be a subscriber)
- `:run_cleanup_needed` -- archive pipeline, reset tasks

Factory **must NOT**:
- Import Workshop prompt modules into compilation logic
- Call Infrastructure directly (use signals or TeamLaunch contract)
- Bypass Ash for durable state writes (PipelineTask must go through Ash actions)
