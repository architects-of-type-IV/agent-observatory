---
id: UC-0102
title: Self-schedule task poll and health check intervals
status: draft
parent_fr: FR-4.3
adrs: [ADR-007]
---

# UC-0102: Self-Schedule Task Poll and Health Check Intervals

## Intent
SwarmMonitor independently maintains two recurring timers: a 3-second task poll and a 30-second health check. Both are self-scheduling -- each handler reschedules itself before doing work -- so that a slow operation in one cycle does not delay the next and a crash in the handler body does not silently stop future cycles.

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- Erlang runtime scheduler (via `Process.send_after/3`)
- `handle_info(:poll_tasks, state)` clause
- `handle_info(:health_check, state)` clause

## Preconditions
- SwarmMonitor `init/1` has completed successfully.
- The process mailbox is accepting messages.

## Trigger
`init/1` sends the first `:poll_tasks` message immediately and schedules the first `:health_check` message after 5,000 ms.

## Main Success Flow
1. `init/1` calls `send(self(), :poll_tasks)` and `Process.send_after(self(), :health_check, 5_000)`.
2. `handle_info(:poll_tasks, state)` fires, calls `Process.send_after(self(), :poll_tasks, 3_000)` as its first action, then performs discovery and parsing.
3. `handle_info(:health_check, state)` fires at T+5s, calls `Process.send_after(self(), :health_check, 30_000)` as its first action, then runs the health script.
4. Both cycles continue independently; a delayed health check does not block a task poll.

## Alternate Flows

### A1: Exception inside handle_info body
Condition: A runtime error occurs after the reschedule call has already been made.
Steps:
1. The next timer is already registered before the error.
2. The exception propagates and the supervisor restarts SwarmMonitor.
3. After restart, `init/1` re-establishes both schedules from scratch.

## Failure Flows

### F1: Reschedule call omitted
Condition: A code change removes `Process.send_after` from `handle_info(:poll_tasks, state)`.
Steps:
1. The first poll fires but no second poll is scheduled.
2. Polling stops permanently after the first cycle.
3. The dashboard freezes on stale task state.
Result: This is a programming error. The reschedule call MUST be the first line of each handler.

## Gherkin Scenarios

### S1: Task poll recurs every 3 seconds
```gherkin
Scenario: Task poll fires repeatedly at 3-second intervals
  Given SwarmMonitor has just started
  When 10 seconds elapse
  Then :poll_tasks has fired at least 3 times
  And each firing reschedules the next :poll_tasks message
```

### S2: Health check fires 5 seconds after start then every 30 seconds
```gherkin
Scenario: Health check deferred 5 seconds then recurs at 30-second intervals
  Given SwarmMonitor has just started
  When 5 seconds elapse
  Then :health_check fires for the first time
  And the next :health_check is scheduled 30 seconds later
```

### S3: Health check delay does not delay task poll
```gherkin
Scenario: Slow health check does not block concurrent task polls
  Given the health check script takes 8 seconds to complete
  When :poll_tasks fires during the health check
  Then the poll completes and its results are broadcast without waiting for the health check
```

## Acceptance Criteria
- [ ] After starting SwarmMonitor in a test process, asserting `receive {:swarm_state, _}` with a 4-second timeout succeeds at least twice consecutively, confirming recurrence (S1).
- [ ] `SwarmMonitor.get_state().health` is populated (non-nil) within 40 seconds of startup when the health script is present (S2).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Timer messages `:poll_tasks` and `:health_check` delivered to process mailbox
**Outputs:** Updated state broadcast on `"swarm:update"` after each poll; health map updated after each health check
**State changes:** `state.tasks`, `state.pipeline`, `state.dag`, `state.stale_tasks`, `state.file_conflicts` refreshed on each poll; `state.health` refreshed on each health check

## Traceability
- Parent FR: [FR-4.3](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
