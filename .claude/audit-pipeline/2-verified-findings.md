# Stage 2: Verified Findings -- Ash Idiomacy Audit

```
CONFIRMED: 16 high, 18 medium
REJECTED:  1 (H13 false positive -- emit_scoped IS in code_interface)
REVIEW:    0
```

---

## CONFIRMED HIGH (16)

### H1. after_action side effect -> notifier
- `sync_pipeline_process.ex:10-17` -- CONFIRMED. `after_action` calls GenServer, forces `require_atomic?(false)` on 4 actions.

### H2. task_count -> aggregate
- `pipeline.ex:57-59` -- CONFIRMED. Stored integer with `has_many :pipeline_tasks` relationship. Should be `count :task_count, :pipeline_tasks`.

### H3. get_run_status counts -> aggregates
- `pipeline.ex:117-151` -- CONFIRMED. Fetches all tasks, maps to graph nodes, computes stats. 5 aggregate declarations would replace this.

### H4. Signals.emit in action body -> notifier
- `project.ex:877,901` -- CONFIRMED. `Signals.emit(:project_artifact_created, ...)` fires pre-commit.

### H5. __MODULE__ self-read with bang
- `agent.ex:77-79`, `active_team.ex:48-49` -- CONFIRMED. `Ash.read!()` in generic action run.

### H6. allow_nil? missing on tool arguments
- `agent.ex:147-170,213-258`, `active_team.ex:74,114` -- CONFIRMED. `:team_name`, `:backend`, `:instructions`, `:project` lack `allow_nil?: false`.

### H7. Private helpers in resource body
- `agent.ex:392+` -- CONFIRMED (scout read full file). `spawn_in_fleet/2`, `find_agent/1`, `build_agent_match/3`.

### H8. Resource as pure action container
- `agent_memory.ex` -- CONFIRMED. Zero attributes, zero relationships, no data layer.

### H9. Missing error clause in run fn
- `agent_memory.ex:305-322` -- CONFIRMED (scout read). Only matches `{:ok, agents}`, no `{:error, _}`.

### H10. normalize_status(:paused) -> :idle lossy
- `load_agents.ex:53` -- CONFIRMED. `defp normalize_status(:paused), do: :idle`

### H11. health: :healthy hardcoded
- `load_agents.ex:31` -- CONFIRMED. All agents stamped `:healthy` without computation.

### H12. Duplicated load logic
- `tool_failure.ex:41-57` -- CONFIRMED. `load_recent_errors/0` duplicates `LoadToolFailures.prepare/3`.

### H14. try/rescue for control flow
- `operations.ex:17-33` -- CONFIRMED. Rescues RuntimeError/ArgumentError/KeyError instead of checking process state.

### H15. Redundant fallback + Enum.take
- `operations.ex:103,106,110` -- CONFIRMED. `default: 20` + `|| 20` + double `Enum.take`.

### H16. allow_nil? with no default but body falls back
- `operations.ex:151,154` -- CONFIRMED. `allow_nil?: false` but no default, body does `|| 30`.

### H17. Redundant set_attribute
- `webhook_delivery.ex:40-41` -- CONFIRMED. `:status` and `:attempt_count` changes duplicate attribute defaults.

---

## REJECTED (1)

### ~~H13. emit_scoped missing from code_interface~~ -- FALSE POSITIVE
- `event.ex:12` has `define(:emit_scoped, args: [:name, :scope_id])`. Scout misread.

---

## CONFIRMED MEDIUM (18)

All medium findings confirmed by scout file reads. Key ones:

- **M1**: `team.ex:78` `require_atomic?(false)` with no fn-based changes -- CONFIRMED
- **M2**: Near-duplicate spawn actions in `agent.ex` -- CONFIRMED
- **M8**: Helpers on resource should be in ProjectView -- CONFIRMED
- **M9**: Generic actions call raw Changeset.for_update -- CONFIRMED
- **M11**: Bang calls in `infrastructure/operations.ex` -- CONFIRMED
- **M15**: No code_interface on 3 Operations resources -- CONFIRMED
- **M17**: Optional `:category` lacks explicit allow_nil? -- CONFIRMED
- **M18**: allow_nil? missing on attributes with defaults in `agent_type.ex` -- CONFIRMED

Others (M3-M7, M10, M12-M14, M16): confirmed as noted in scout reports.
