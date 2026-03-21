# Stage 3: Execution Plan -- Ash Idiomacy Audit

Build command: `mix compile --warnings-as-errors`

---

## TASK 1: Signals Operations cleanup (H14, H15, H16)
**FILES**: `lib/ichor/signals/operations.ex`
**CHANGES**:
- L17-33: Replace `try/rescue` in `check_operator_inbox` with `AgentProcess.alive?` guard (same pattern as `check_inbox` on L43)
- L106: Remove `|| 20` fallback (redundant with `default: 20`)
- L110: Remove `|> Enum.take(limit)` (redundant with `Bus.recent_messages(limit)`)
- L151: Add `default: 30` to `:limit` argument
- L154: Remove `|| 30` fallback
**DEPENDS_ON**: none

## TASK 2: WebhookDelivery redundant set_attribute (H17)
**FILES**: `lib/ichor/infrastructure/webhook_delivery.ex`
**CHANGES**:
- L40: Remove `change(set_attribute(:status, :pending))` -- attribute default is already `:pending`
- L41: Remove `change(set_attribute(:attempt_count, 0))` -- attribute default is already `0`
**DEPENDS_ON**: none

## TASK 3: Pipeline aggregates (H2, H3)
**FILES**: `lib/ichor/factory/pipeline.ex`
**CHANGES**:
- L57-60: Remove `task_count` stored attribute
- Add `aggregates do count :task_count, :pipeline_tasks end`
- L76: Remove `:task_count` from create accept list
- L117-151: Refactor `get_run_status` to use aggregates instead of fetching all tasks. Add status-filtered count aggregates: `pending_count`, `in_progress_count`, `completed_count`, `failed_count`
- Note: `get_run_status` also returns `nodes` for graph display. If PipelineGraph.to_graph_node is only used for stats, remove it. If used for graph visualization elsewhere, keep the task fetch but use aggregates for stats.
**CONSTRAINTS**:
- Migration needed: `mix ash.codegen remove_task_count_from_pipelines` to drop the column
- Verify `Spawn.from_file` doesn't set `task_count` on create -- if it does, update it to omit that field
**DEPENDS_ON**: none

## TASK 4: SyncPipelineProcess -> Notifier (H1)
**FILES**:
- `lib/ichor/factory/pipeline_task/changes/sync_pipeline_process.ex` (modify or delete)
- `lib/ichor/factory/pipeline_task.ex` (remove change references, add notifier)
**CHANGES**:
- Convert `SyncPipelineProcess` from `Ash.Resource.Change` to `Ash.Notifier`
- Register as `simple_notifiers: [Ichor.Factory.PipelineTask.Notifiers.SyncRunner]` on PipelineTask
- In the notifier, match on `{PipelineTask, action_name}` for `:claim`, `:complete`, `:fail`, `:reset`
- Remove `change(Ichor.Factory.PipelineTask.Changes.SyncPipelineProcess)` from all 4 update actions
- Remove `require_atomic?(false)` from those actions IF no other fn-based changes remain
**CONSTRAINTS**:
- Do NOT modify Runner module
- Keep the `Code.ensure_loaded?` guard in the notifier
**DEPENDS_ON**: none

## TASK 5: Workshop Agent/ActiveTeam bang -> non-bang (H5, H6)
**FILES**:
- `lib/ichor/workshop/agent.ex`
- `lib/ichor/workshop/active_team.ex`
**CHANGES**:
- `agent.ex:77-79`: Replace `Ash.read!()` with `Ash.read()` + `with` or `case`
- `active_team.ex:48-49`: Same -- replace `Ash.read!()` with `Ash.read()`
- `agent.ex:147-170`: Add `allow_nil?: false` with sensible defaults to `:team_name` (default ""), `:backend` (default %{}), `:instructions` (default "")
- `agent.ex:213-258`: Add `allow_nil?: false` with defaults to `:name` (default ""), `:cwd` (default ""), `:team_name` (default ""), `:extra_instructions` (default "")
- `active_team.ex:74`: Add `allow_nil?: false, default: ""` to `:project`
- `active_team.ex:114`: Add `allow_nil?: false, default: %{}` to `:backend`
**CONSTRAINTS**:
- Do NOT restructure actions or move code -- only fix bang and allow_nil
**DEPENDS_ON**: none

## TASK 6: Agent resource helpers -> utility module (H7)
**FILES**:
- `lib/ichor/workshop/agent.ex` (remove helpers)
- `lib/ichor/workshop/agent_lookup.ex` (create -- new utility module)
**CHANGES**:
- Extract `spawn_in_fleet/2`, `find_agent/1`, `build_agent_match/3` to `Ichor.Workshop.AgentLookup`
- Update callers in agent.ex action run fns to call `AgentLookup.spawn_in_fleet/2` etc.
**DEPENDS_ON**: none

## TASK 7: AgentMemory error handling (H9)
**FILES**: `lib/ichor/workshop/agent_memory.ex`
**CHANGES**:
- L305-322: Add `{:error, reason} -> {:error, reason}` clause to the `case MemoryStore.list_agents()` match
- Audit all other `case` blocks in this file for missing error clauses
**DEPENDS_ON**: none

## TASK 8: LoadAgents health + status (H10, H11)
**FILES**: `lib/ichor/workshop/preparations/load_agents.ex`
**CHANGES**:
- L31: Replace `health: :healthy` with actual health computation using `AgentHealth.compute_agent_health/2` (same as LoadTeams uses)
- L53: Either add `:paused` to Agent's status constraint `one_of` OR add a comment documenting the lossy mapping is intentional
**CONSTRAINTS**:
- If adding `:paused` to status constraint, verify no downstream code assumes only 3 values
**DEPENDS_ON**: none

## TASK 9: ToolFailure deduplicate load logic (H12)
**FILES**: `lib/ichor/signals/tool_failure.ex`
**CHANGES**:
- Remove `load_recent_errors/0` private function
- Refactor `:by_tool` action to call the `:recent` read action (via code interface `ToolFailure.recent()`) instead of duplicating the load logic
- Keep `group_by_tool/1` as the only private helper
**DEPENDS_ON**: none

## TASK 10: Project.ex signals -> notifier (H4)
**FILES**: `lib/ichor/factory/project.ex`
**CHANGES**:
- L877-881, L901-905: Remove `Signals.emit(:project_artifact_created, ...)` from `create_artifact_for` and `create_roadmap_for`
- Add signal emission to `FromAsh` notifier (or a new `Project`-specific notifier) matching on `{Project, :update}` when artifacts/roadmap change
**CONSTRAINTS**:
- The signal data includes `a.id` and `kind` -- the notifier will need to extract this from the changeset or result
- This may require a custom notifier rather than extending FromAsh
**DEPENDS_ON**: none

## TASK 11: Medium fixes batch -- Team, Operations, CronJob, Manager (M1, M10, M11, M14, M17)
**FILES**:
- `lib/ichor/workshop/team.ex`
- `lib/ichor/archon/manager.ex`
- `lib/ichor/infrastructure/operations.ex`
- `lib/ichor/infrastructure/cron_job.ex`
- `lib/ichor/signals/event.ex`
**CHANGES**:
- `team.ex:78`: Remove `require_atomic?(false)` -- no fn-based changes on update
- `manager.ex:43`: Replace `Ash.ActionInput.get_argument(input, :domain)` with `input.arguments.domain`
- `infrastructure/operations.ex:19-20`: Replace `Agent.all!()` and `ActiveTeam.alive!()` with non-bang + error handling
- `cron_job.ex:84`: Change `define(:get, action: :all_scheduled, get_by: [:id])` to `define(:get, get_by: [:id])` (use default read)
- `event.ex:79`: Add explicit `allow_nil?(true)` to `:category` argument
**DEPENDS_ON**: none

## TASK 12: Medium fixes batch -- agent_type allow_nil (M18)
**FILES**: `lib/ichor/workshop/agent_type.ex`
**CHANGES**:
- Add `allow_nil?(false)` to all attributes that have defaults but lack the constraint
**DEPENDS_ON**: none

---

## Execution Order

All tasks are **independent** -- can run in parallel.

Tasks 1-2, 5, 7, 9, 11-12 are small (single-file or trivial multi-file).
Tasks 3, 4, 6, 8, 10 are medium (require new modules or migrations).

**Recommended**: Run all 12 in parallel, 3 agents of ~4 tasks each.
