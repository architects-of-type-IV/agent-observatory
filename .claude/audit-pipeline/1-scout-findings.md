# Stage 1: Scout Findings -- Ash Idiomacy Audit

Scanned: 5 Domains, 33 Resources. Found **44 instances** across ~25 files.

---

## HIGH CONFIDENCE (17)

### H1. Side effect in `after_action` should be notifier
- `lib/ichor/factory/pipeline_task/changes/sync_pipeline_process.ex:10-17`
- Forces `require_atomic?(false)` on 4 update actions

### H2. `task_count` should be aggregate, not stored attribute
- `lib/ichor/factory/pipeline.ex:57-59`
- Pipeline has `has_many :pipeline_tasks`. Use `count :task_count, :pipeline_tasks`

### H3. `get_run_status` computes counts that should be aggregates
- `lib/ichor/factory/pipeline.ex:117-151`
- Fetches all tasks to count by status. Textbook aggregates.

### H4. `Signals.emit` side effects in action run body
- `lib/ichor/factory/project.ex:877-882, 901`
- Fires before transaction commits. Should be notifier.

### H5. `__MODULE__` self-read with bang inside generic action run
- `lib/ichor/workshop/agent.ex:76-94`, `lib/ichor/workshop/active_team.ex:42-67`
- Bang raises bypass Ash error pipeline.

### H6. `allow_nil?: false` missing on tool arguments
- `lib/ichor/workshop/agent.ex:147-170,213-258`
- `lib/ichor/workshop/active_team.ex:71-92,108-130`
- OpenAI schema compatibility rule.

### H7. Private helpers in Resource body
- `lib/ichor/workshop/agent.ex:392-435`
- `spawn_in_fleet/2`, `find_agent/1`, `build_agent_match/3` as `defp` in resource

### H8. Resource as pure action container (no attributes/data)
- `lib/ichor/workshop/agent_memory.ex`
- Zero attributes, zero relationships, no data layer -- only generic actions

### H9. Missing error clause in `run` fn
- `lib/ichor/workshop/agent_memory.ex:305-322`
- CaseClauseError risk if MemoryStore returns error

### H10. `normalize_status(:paused)` maps to `:idle` -- lossy
- `lib/ichor/workshop/preparations/load_agents.ex:53`
- Pause/resume is first-class but status constraint excludes `:paused`

### H11. `health: :healthy` hardcoded, no computation
- `lib/ichor/workshop/preparations/load_agents.ex:31`
- `LoadTeams` computes real health; `LoadAgents` skips it entirely

### H12. Duplicated load logic vs preparation
- `lib/ichor/signals/tool_failure.ex:41-57`
- `load_recent_errors/0` duplicates `LoadToolFailures.prepare/3`

### H13. `emit_scoped` missing from `code_interface`
- `lib/ichor/signals/event.ex`
- Callers must use lower-level `Ash.run_action/2`

### H14. `try/rescue` for normal control flow
- `lib/ichor/signals/operations.ex:17-33`
- Should check process alive first or use error tuples

### H15. Redundant fallback + duplicate `Enum.take`
- `lib/ichor/signals/operations.ex:105-106`
- Default already ensures value. Take is redundant after `Bus.recent_messages(limit)`

### H16. `allow_nil?: false` with no default but body falls back
- `lib/ichor/signals/operations.ex:151-154`
- Contradictory. Add `default: 30` or remove `allow_nil?: false`

### H17. Redundant `set_attribute` changes duplicate attribute defaults
- `lib/ichor/infrastructure/webhook_delivery.ex:40-43`
- `:status` and `:attempt_count` already have matching defaults

---

## MEDIUM CONFIDENCE (18)

### M1. `require_atomic?(false)` with no fn-based changes -- `team.ex:78`
### M2. Near-duplicate actions `spawn_agent`/`spawn_archon_agent` -- `agent.ex:260-335`
### M3. `:map` attributes for known shapes (ephemeral) -- `agent.ex:42-54`, `active_team.ex:19`
### M4. Runtime `Code.ensure_loaded?` guards -- `sync_pipeline_process.ex:21-23`
### M5. N+1: full `by_run` query when only status+external_id needed -- `filter_available.ex:17-27`
### M6. `artifact/1` and `roadmap_item/1` bypass embedded resource create -- `project.ex:874`
### M7. Concurrent read-modify-write on embedded arrays -- `project.ex:915-930`
### M8. Helpers on resource should be in ProjectView -- `project.ex:946-948`
### M9. Generic actions call raw `Ash.Changeset.for_update` instead of code interface -- `pipeline_task.ex:231`
### M10. `Ash.ActionInput.get_argument/2` instead of `input.arguments.domain` -- `manager.ex:43`
### M11. Bang calls inside run fn bypass error handling -- `infrastructure/operations.ex:19-20`
### M12. Three single-filter read actions verbose -- `hitl_intervention_event.ex:55-71`
### M13. `enqueue` code interface args omits `:webhook_id` -- `webhook_delivery.ex:75`
### M14. `define(:get, action: :all_scheduled, get_by: [:id])` runs sort on ID lookup -- `cron_job.ex:84`
### M15. No `code_interface` block (inconsistent) -- `operations.ex` x3, `manager.ex`
### M16. `:by_tool` return type hides known shape -- `tool_failure.ex:28-33`
### M17. Optional `:category` lacks explicit `allow_nil?(true)` -- `event.ex:79`
### M18. `allow_nil?: false` missing on attributes with defaults -- `agent_type.ex:43-55`

---

## LOW CONFIDENCE (9)

### L1-L9: Informational items (embedded resource registration, dot notation, etc.)
