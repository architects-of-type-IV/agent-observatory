---
id: UC-0114
title: Prune oldest traces when ETS table exceeds 200 entries
status: draft
parent_fr: FR-4.15
adrs: [ADR-007]
---

# UC-0114: Prune Oldest Traces When ETS Table Exceeds 200 Entries

## Intent
After every new trace is inserted into the `:protocol_traces` ETS table, ProtocolTracker checks the total count. When the count exceeds 200, the oldest entries (sorted by `timestamp` ascending) are deleted until exactly 200 remain. This prevents unbounded memory growth without requiring a separate cleanup timer.

## Primary Actor
`Observatory.ProtocolTracker`

## Supporting Actors
- ETS table `:protocol_traces`
- Internal `prune_traces/0` function
- Internal `insert_trace/1` function

## Preconditions
- The `:protocol_traces` ETS table exists.
- `insert_trace/1` has just written a new entry.

## Trigger
`insert_trace/1` calls `prune_traces/0` synchronously after writing to ETS.

## Main Success Flow
1. `insert_trace/1` writes the new trace to ETS.
2. `prune_traces/0` is called immediately.
3. All entries are read from the table and their `timestamp` fields are compared.
4. If the count is <= 200, no deletion occurs.
5. If the count is 201, the entry with the oldest `timestamp` is deleted via `:ets.delete/2`.
6. The table now contains exactly 200 entries.

## Alternate Flows

### A1: Table count is exactly 200 after insert
Condition: The table held 199 entries before the insert.
Steps:
1. Count after insert is 200.
2. `prune_traces/0` finds count <= 200 and returns without deleting.

### A2: Multiple entries with identical timestamps
Condition: Two traces have the same `timestamp` value.
Steps:
1. Both are candidates for deletion if one must be removed.
2. Either may be deleted (ordering between them is non-deterministic).
3. Exactly one is deleted when count is 201.

## Failure Flows

### F1: prune_traces not called after insert
Condition: A code change omits the `prune_traces/0` call from `insert_trace/1`.
Steps:
1. The table grows without bound.
2. `get_traces/0` performance degrades over time.
Result: This is a programming error. The prune call MUST be the last line of `insert_trace/1`.

## Gherkin Scenarios

### S1: 201st entry triggers deletion of the oldest
```gherkin
Scenario: Inserting the 201st trace removes the oldest entry
  Given the :protocol_traces table contains exactly 200 entries
  And the oldest entry has timestamp ~U[2026-02-21T10:00:00Z]
  When a new trace is inserted
  Then the table contains exactly 200 entries
  And the entry with timestamp ~U[2026-02-21T10:00:00Z] is no longer present
```

### S2: 200th entry does not trigger deletion
```gherkin
Scenario: Inserting the 200th trace leaves the table at 200
  Given the :protocol_traces table contains 199 entries
  When a new trace is inserted
  Then the table contains exactly 200 entries
  And no entries are deleted
```

### S3: Large burst of inserts keeps table at cap
```gherkin
Scenario: 50 rapid inserts into a full table keeps the table at 200
  Given the table contains 200 entries
  When 50 new traces are inserted sequentially
  Then the table contains exactly 200 entries after all inserts
  And the 50 newest traces are present
  And 50 of the original entries have been deleted
```

## Acceptance Criteria
- [ ] A unit test that inserts 201 traces asserts `:ets.info(:protocol_traces, :size) == 200` after the 201st insert (S1).
- [ ] A unit test that inserts 200 traces asserts `:ets.info(:protocol_traces, :size) == 200` and no deletions occurred (S2).
- [ ] A unit test that inserts 250 traces into a previously full table asserts `:ets.info(:protocol_traces, :size) == 200` (S3).
- [ ] The oldest trace (lowest timestamp) is the one deleted in the S1 scenario.
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** ETS table current state; newly inserted trace
**Outputs:** ETS table with count at or below 200; oldest entry deleted when over limit
**State changes:** `:protocol_traces` has one or more entries removed when over the 200-entry cap

## Traceability
- Parent FR: [FR-4.15](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
