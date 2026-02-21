---
id: UC-0111
title: Start ProtocolTracker with ETS table and event stream subscription
status: draft
parent_fr: FR-4.12
adrs: [ADR-007]
---

# UC-0111: Start ProtocolTracker with ETS Table and Event Stream Subscription

## Intent
On startup, `Observatory.ProtocolTracker` creates a public named ETS table for trace storage and subscribes to the `"events:stream"` PubSub topic. After a crash and restart, the table is recreated and traces start fresh, which is acceptable because traces are ephemeral observability data.

## Primary Actor
`Observatory.ProtocolTracker`

## Supporting Actors
- `Observatory.Application` supervisor
- ETS (`:ets.new/2`)
- `Phoenix.PubSub` (subscription to `"events:stream"`)

## Preconditions
- `Phoenix.PubSub` is started before `ProtocolTracker` in the supervision tree.
- `Observatory.SwarmMonitor` is already started (appears before `ProtocolTracker` in child list).

## Trigger
`Observatory.Application` starts `ProtocolTracker` as a supervised child.

## Main Success Flow
1. `ProtocolTracker.start_link/1` is called by the supervisor.
2. `init/1` creates the ETS table `:protocol_traces` as `[:named_table, :public, :set]`.
3. `init/1` subscribes to `"events:stream"` via `Phoenix.PubSub.subscribe/2`.
4. The process is registered under `Observatory.ProtocolTracker`.
5. `:ets.info(:protocol_traces)` returns a non-nil tuple confirming the table exists.
6. `ProtocolTracker.get_traces/0` queries the table directly without a GenServer call.

## Alternate Flows

### A1: Table queried immediately after startup
Condition: `get_traces/0` is called before any events arrive.
Steps:
1. `:ets.tab2list(:protocol_traces)` returns `[]`.
2. `get_traces/0` returns `[]` sorted by timestamp (empty).

## Failure Flows

### F1: ProtocolTracker crashes
Condition: An unhandled exception occurs inside a `handle_info` clause.
Steps:
1. The ETS table `:protocol_traces` is destroyed because the owning process died.
2. The supervisor restarts `ProtocolTracker`.
3. `init/1` re-creates the table and re-subscribes to `"events:stream"`.
4. All previous traces are lost; the table starts empty.
Result: Trace history is ephemeral and lost on crash. This is acceptable by design.

## Gherkin Scenarios

### S1: ETS table exists after startup
```gherkin
Scenario: ProtocolTracker creates the :protocol_traces ETS table on init
  Given Observatory.Application is starting
  When ProtocolTracker starts
  Then :ets.info(:protocol_traces) returns a non-nil value
  And ProtocolTracker.get_traces() returns an empty list
```

### S2: Crash and restart recreates the table
```gherkin
Scenario: ETS table is recreated after a ProtocolTracker crash
  Given ProtocolTracker is running with 5 traces in the table
  When Process.exit(ProtocolTracker, :kill) is called
  Then the supervisor restarts ProtocolTracker
  And :ets.info(:protocol_traces) returns a non-nil value after restart
  And ProtocolTracker.get_traces() returns an empty list (traces lost)
```

## Acceptance Criteria
- [ ] After application boot, `:ets.info(:protocol_traces)` does not return `undefined` (S1).
- [ ] `ProtocolTracker.get_traces()` returns a list (possibly empty) without raising (S1).
- [ ] Killing the ProtocolTracker process results in a restart and a fresh empty `:protocol_traces` table within 1 second (S2).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** None (startup-only; no arguments required)
**Outputs:** Named ETS table `:protocol_traces`; PubSub subscription on `"events:stream"`
**State changes:** ETS table created in OTP process table; PubSub subscription registered

## Traceability
- Parent FR: [FR-4.12](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
