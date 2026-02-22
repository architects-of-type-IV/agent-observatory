---
id: UC-0018
title: Close existing Fact validity window on contradiction and create replacement
status: draft
parent_fr: FR-0044
adrs: [ADR-001]
---

# UC-0018: Close Existing Fact Validity Window on Contradiction and Create Replacement

## Intent
When a new Fact contradicts an existing currently-valid Fact (same subject, predicate, overlapping validity), atomically close the existing Fact's world-time validity window and persist the new Fact as its replacement.

## Primary Actor
Ash Reactor Step (`InvalidateSupersededFacts` step inside the DigestEpisode Reactor, triggered by `UpsertFacts`).

## Supporting Actors
- `Memories.API.Resources.Fact` Ash resource (update and create actions)
- AshPostgres.DataLayer (atomic write sequence)
- Oban worker (`API.Jobs.DigestEpisodeWorker`) for retry lifecycle

## Preconditions
- A valid `group_id` tenant context is active (established via `tenant: group_id` in Ash action options).
- Two Entity records exist under `group_id` (to serve as `subject` and `object` for the Fact fixture).
- An initial Fact is created via `Ash.create(Fact, %{fact: "...", subject_id: subject.id, object_id: object.id, predicate: "PREDICATE", valid_at: ~U[2025-01-01 00:00:00Z], group_id: group_id}, tenant: group_id)` with `invalid_at: nil`.
- The existing Fact's validity period overlaps with the new Fact's `valid_at`. Because the existing Fact has `invalid_at` null (open-ended validity), any new Fact's `valid_at` creates an overlap -- no additional setup is required to satisfy this condition.

## Trigger
The `InvalidateSupersededFacts` Reactor step detects a contradiction between an incoming new Fact and an existing currently-valid Fact during DigestEpisode execution.

## Main Success Flow
1. The step loads the existing Fact matching `(group_id, subject_id, predicate)` with `invalid_at` null.
2. The step calls the Fact update action: `invalid_at: new_fact.valid_at`, `invalidation_reason: :contradiction`.
3. AshPostgres commits the update; the existing Fact now has `invalid_at` set and `invalidation_reason: :contradiction`.
4. The step calls the Fact create action to persist the new Fact with all its fields.
5. AshPostgres persists the new Fact; action returns `{:ok, new_fact}`.
6. The existing Fact is preserved in the database but excluded from current-state queries.
7. The new Fact appears in current-state queries.

## Alternate Flows

### A1: No existing contradicting Fact found
Condition: No Fact with the same `(group_id, subject_id, predicate)` and `invalid_at` null exists.
Steps:
1. The contradiction detection finds no match.
2. The new Fact is created directly without any invalidation step.
3. No existing record is modified.

## Failure Flows

### F1: Invalidation update fails before new Fact creation
Condition: The update action for the existing Fact fails (e.g., database error).
Steps:
1. Ash returns `{:error, changeset}` from the update action.
2. The Reactor step propagates the error; no new Fact is created.
3. The existing Fact remains unmodified (still `invalid_at` null, still appears as currently valid).
4. The Oban worker marks the job as failed; Oban retries from the beginning.
Result: No partial state (new fact without invalidated old fact); the job is retried safely.

### F2: New Fact creation fails after successful invalidation
Condition: The invalidation update commits but the create action for the new Fact fails.
Steps:
1. The existing Fact now has `invalid_at` set (committed).
2. The new Fact create action fails.
3. The Reactor step propagates the error.
4. The Oban job is retried; the retry encounters the already-invalidated Fact and creates the new Fact on the second attempt.
Result: The retry is safe because the idempotency key (FR-0047) prevents a duplicate new Fact if creation partially succeeded.

## Gherkin Scenarios

### S1: Successful contradiction invalidation and replacement
```gherkin
Scenario: Invalidate existing Fact on contradiction and create replacement
  Given an existing Fact with subject_id, predicate "PREDICATE", and invalid_at null under group_id
  And a new Fact with the same subject_id and predicate but a later valid_at
  When the InvalidateSupersededFacts step detects the contradiction
  Then the existing Fact has invalid_at set to new_fact.valid_at
  And the existing Fact has invalidation_reason set to :contradiction
  And a new Fact is created with invalid_at null
  And the existing Fact is excluded from current-state queries
  And the new Fact appears in current-state queries
```

### S2: No existing contradicting Fact
```gherkin
Scenario: Create Fact directly when no contradiction exists
  Given no Fact with the same subject_id, predicate, and invalid_at null exists under group_id
  When the InvalidateSupersededFacts step runs
  Then the new Fact is created without any invalidation
  And no existing Fact records are modified
```

### S3: Invalidation update fails before new Fact creation
```gherkin
Scenario: Rollback safely when invalidation update fails
  Given an existing Fact with invalid_at null under group_id
  When the Fact update action returns {:error, changeset}
  Then no new Fact is created
  And the existing Fact remains unmodified with invalid_at null
  And the Oban worker marks the job as failed for retry
```

### S4: Retry after partial failure (invalidation committed, creation failed)
```gherkin
Scenario: Retry creates replacement Fact after prior partial failure
  Given an existing Fact with invalid_at already set and invalidation_reason :contradiction
  And no replacement Fact exists yet
  When the Oban job retries and the creation step runs
  Then a new replacement Fact is created successfully
  And no duplicate Fact is created due to the idempotency key
```

## Acceptance Criteria
- [ ] `mix test test/memories/api/resources/fact_test.exs` passes a test that creates an existing Fact, then invokes the contradiction flow, and asserts the existing Fact has `invalid_at: new_fact.valid_at` and `invalidation_reason: :contradiction` (S1).
- [ ] The same test asserts a new Fact was created and `new_fact.invalid_at` is null (S1).
- [ ] The same test asserts the existing Fact is NOT returned by a current-state query after invalidation (S1).
- [ ] A test asserts partial-state safety via the F1 path: manually create a Fact record with `invalid_at` already set but no replacement Fact; verify that a second call to the contradiction flow (treating this as a retry) creates the new Fact without error (S4). Mechanism: directly call `Ash.update(existing_fact, %{invalid_at: ...})` in the test setup to simulate committed invalidation, then run the upsert step and assert the new Fact is created.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data

**Inputs:**
- Existing Fact: `(group_id, subject_id, predicate)` with `invalid_at` null
- New Fact params: all Fact fields including `valid_at`

**Outputs:**
- Updated existing Fact: `invalid_at = new_fact.valid_at`, `invalidation_reason = :contradiction`
- Newly created Fact (the replacement)

**State changes:**
- `facts.invalid_at` -- set on existing Fact to `new_fact.valid_at`
- `facts.invalidation_reason` -- set to `:contradiction` on existing Fact
- New row inserted into `facts` for the replacement Fact

## Traceability
- Parent FR: [FR-0044](../frs/FR-0044-contradiction-invalidation-flow.md)
- ADR: [ADR-001](../../decisions/ADR-001-bi-temporal-model.md)
