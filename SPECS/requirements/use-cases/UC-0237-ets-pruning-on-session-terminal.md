---
id: UC-0237
title: Prune the Session ETS Table Five Minutes After Terminal Signal
status: draft
parent_fr: FR-8.8
adrs: [ADR-017]
---

# UC-0237: Prune the Session ETS Table Five Minutes After Terminal Signal

## Intent
When a session is declared terminal, its DAG data must remain accessible for five minutes to allow in-flight drill-down views to complete, then be permanently deleted. `CausalDAG` must schedule this deletion automatically on receiving the terminal signal, ignore any duplicate terminal signals that arrive before the timer fires, and return `{:error, :session_not_found}` for any query made after deletion.

## Primary Actor
CausalDAG

## Supporting Actors
- Session lifecycle event bus (source of `is_terminal: true` signals)
- ETS table keyed by `{session_id, trace_id}`
- Erlang Process timer (`:timer.apply_after` or equivalent)

## Preconditions
- `CausalDAG` GenServer is running.
- The session has an active ETS table with at least one node.

## Trigger
`CausalDAG` receives a session lifecycle event with `control.is_terminal == true` for a `session_id`.

## Main Success Flow
1. `CausalDAG` receives the terminal signal for `session_id` "sess-xyz" at time T.
2. `CausalDAG` schedules deletion of the session's ETS table for T + 5 minutes using a one-shot timer.
3. During the 5-minute window, `get_session_dag/1` continues to return `{:ok, %{...}}` normally.
4. At T + 5 minutes, the timer fires and `CausalDAG` deletes the ETS table.
5. Any subsequent call to `get_session_dag("sess-xyz")` returns `{:error, :session_not_found}`.

## Alternate Flows
None defined — the 5-minute grace period is fixed.

## Failure Flows
### F1: Duplicate terminal signal arrives before timer fires
Condition: A second `is_terminal: true` signal arrives for the same session while the 5-minute timer is already running.
Steps:
1. `CausalDAG` receives the second signal.
2. `CausalDAG` checks whether a deletion timer is already scheduled for this session.
3. The existing timer is NOT reset or extended — it continues to fire at the original T + 5.
4. The duplicate signal is silently discarded.
Result: ETS table is deleted exactly once, at the originally scheduled time.

## Gherkin Scenarios

### S1: ETS table remains accessible during 5-minute grace window
```gherkin
Scenario: DAG remains queryable during the 5-minute post-terminal window
  Given session "sess-xyz" receives a terminal signal at time T
  And CausalDAG schedules ETS deletion at T plus 5 minutes
  When CausalDAG.get_session_dag/1 is called at T plus 4 minutes
  Then the function returns {:ok, map} with the session's nodes
```

### S2: ETS table deleted and queries fail after 5 minutes
```gherkin
Scenario: DAG is no longer queryable after 5-minute grace period expires
  Given session "sess-xyz" received a terminal signal at time T
  And the 5-minute deletion timer has fired
  When CausalDAG.get_session_dag/1 is called at T plus 5 minutes and 1 second
  Then the function returns {:error, :session_not_found}
```

### S3: Duplicate terminal signal does not reset the deletion timer
```gherkin
Scenario: Second is_terminal signal does not delay ETS deletion
  Given session "sess-xyz" received a terminal signal at time T
  And a deletion timer is scheduled for T plus 5 minutes
  When a second is_terminal signal arrives for "sess-xyz" at T plus 2 minutes
  Then the deletion timer still fires at T plus 5 minutes
  And the ETS table is not deleted early or rescheduled
```

## Acceptance Criteria
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that sends a terminal signal, calls `get_session_dag/1` before the timer fires (via accelerated timer or mock), and asserts the session is still accessible.
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that sends a terminal signal, advances the clock past 5 minutes, and asserts `get_session_dag/1` returns `{:error, :session_not_found}`.
- [ ] `mix test test/observatory/mesh/causal_dag_test.exs` passes a test that sends two terminal signals and asserts the ETS table is deleted exactly once at the originally scheduled time.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Session lifecycle event with `session_id` and `control.is_terminal: true`.
**Outputs:** Deferred ETS table deletion at T+5m; queries return `{:error, :session_not_found}` after deletion.
**State changes:** Session ETS table deleted 5 minutes after terminal signal; one-shot timer registered per session.

## Traceability
- Parent FR: FR-8.8
- ADR: [ADR-017](../../decisions/ADR-017-causal-dag-parent-step-id.md)
