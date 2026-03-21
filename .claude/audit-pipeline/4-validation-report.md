# Stage 5: Validation Report -- Ash Idiomacy Audit

## Results
- **Found (Stage 1)**: 44 (17 high, 18 medium, 9 low)
- **False positives removed (Stage 2)**: 1 (H13)
- **Tasks executed (Stage 4)**: 12
- **Build**: PASS (0 new warnings, 0 errors)
- **Remaining high instances**: 0

## Files Changed (20)

### Modified (16)
1. `lib/ichor/signals/operations.ex` -- try/rescue -> alive? guard, redundant fallbacks removed
2. `lib/ichor/infrastructure/webhook_delivery.ex` -- redundant set_attribute removed
3. `lib/ichor/factory/pipeline.ex` -- task_count attribute removed, stats from tasks
4. `lib/ichor/factory/pipeline_task.ex` -- SyncPipelineProcess change -> notifier
5. `lib/ichor/workshop/agent.ex` -- bang -> non-bang, allow_nil?, helpers extracted
6. `lib/ichor/workshop/active_team.ex` -- bang -> non-bang, allow_nil? added
7. `lib/ichor/workshop/agent_memory.ex` -- error clause added
8. `lib/ichor/workshop/preparations/load_agents.ex` -- health :unknown, status comment
9. `lib/ichor/signals/tool_failure.ex` -- deduplicated via code interface
10. `lib/ichor/factory/project.ex` -- Signals.emit removed (TODO for notifier)
11. `lib/ichor/workshop/team.ex` -- require_atomic? removed
12. `lib/ichor/archon/manager.ex` -- input.arguments.domain
13. `lib/ichor/infrastructure/operations.ex` -- bang -> non-bang
14. `lib/ichor/signals/event.ex` -- allow_nil?(true) on :category
15. `lib/ichor/workshop/agent_type.ex` -- allow_nil?(false) on 6 attributes
16. `lib/ichor/factory/spawn.ex` -- removed task_count from pipeline attrs

### Created (2)
17. `lib/ichor/factory/pipeline_task/notifiers/sync_runner.ex`
18. `lib/ichor/workshop/agent_lookup.ex`

### Deleted (1)
19. `lib/ichor/factory/pipeline_task/changes/sync_pipeline_process.ex` -> tmp/trash/

### Migration (1)
20. `priv/repo/migrations/20260321024007_remove_task_count_from_pipelines.exs`

## Key Discovery
AshSqlite does not support aggregates. Task 3 adapted by computing stats from fetched tasks.
