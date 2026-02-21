---
id: UC-0279
title: Define webhook_deliveries SQLite Table Structure with Compound Index
status: draft
parent_fr: FR-10.8
adrs: [ADR-020]
---

# UC-0279: Define webhook_deliveries SQLite Table Structure with Compound Index

## Intent
This use case covers the creation of the `webhook_deliveries` SQLite table and its companion `webhook_configs` table. The `webhook_deliveries` table provides the durable delivery queue for outbound webhook calls. A compound index on `(status, next_retry_at)` enables the periodic retry poll to efficiently find due entries without a full table scan.

## Primary Actor
`Observatory.Gateway.WebhookRouter`

## Supporting Actors
- SQLite data layer (Ecto adapter)
- Ecto migration system

## Preconditions
- The SQLite database file is configured and accessible.
- `Observatory.Repo` is started.
- A migration file exists in `priv/repo/migrations/` that creates both `webhook_deliveries` and `webhook_configs` tables.

## Trigger
A new inbound webhook event arrives and `WebhookRouter` attempts to create a `webhook_deliveries` row with `status: "pending"`.

## Main Success Flow
1. A webhook event is received by `WebhookRouter`.
2. `WebhookRouter` creates a row in `webhook_deliveries` with `status: "pending"`, `attempt_count: 0`, `next_retry_at` set to 30 seconds from `created_at`, and a computed HMAC-SHA256 signature.
3. The row is committed to the SQLite database.
4. The periodic retry poll queries `WHERE status IN ('pending','failed') AND next_retry_at <= now()` and finds the row immediately on the first poll cycle after `next_retry_at` elapses.
5. The compound index on `(status, next_retry_at)` satisfies the query without a full table scan.

## Alternate Flows
### A1: webhook_configs lookup maps the event to a target
Condition: A `webhook_configs` row exists for the `{source_identifier, event_type}` pair.
Steps:
1. `WebhookRouter` looks up the config row to determine `agent_intent` and `target_session`.
2. The delivery row is created referencing the config row via `webhook_id`.

## Failure Flows
### F1: Missing compound index causes full table scan
Condition: The migration omits the compound index on `(status, next_retry_at)`.
Steps:
1. The retry poll performs a full table scan on `webhook_deliveries`.
2. At scale, this degrades performance.
Result: The migration MUST include `create index(:webhook_deliveries, [:status, :next_retry_at])` to prevent this failure mode.

## Gherkin Scenarios

### S1: webhook_deliveries row created with correct initial state
```gherkin
Scenario: new webhook event creates a pending delivery row with compound index lookup
  Given the webhook_deliveries table exists with the compound index on (status, next_retry_at)
  When WebhookRouter receives a webhook event and creates a delivery row
  Then the row has status "pending", attempt_count 0, and next_retry_at set to 30 seconds from created_at
  And the compound index query WHERE status IN ('pending','failed') AND next_retry_at <= now() finds the row on the first poll
```

### S2: webhook_configs maps source identifier and event type to delivery target
```gherkin
Scenario: webhook_configs row provides agent_intent and target_session for a delivery
  Given a webhook_configs row with source_identifier "github" and event_type "push"
  When WebhookRouter creates a delivery for a matching event
  Then the webhook_deliveries row references the webhook_configs row via webhook_id
  And the delivery payload includes the mapped agent_intent and target_session values
```

### S3: Migration includes the compound index on status and next_retry_at
```gherkin
Scenario: Ecto migration creates the compound index required for efficient retry polling
  Given the migration file for webhook_deliveries is applied via mix ecto.migrate
  When the SQLite schema is inspected
  Then an index exists on the webhook_deliveries table covering both the status and next_retry_at columns
```

## Acceptance Criteria
- [ ] `mix test test/observatory/gateway/webhook_deliveries_test.exs` passes a test that verifies the webhook_deliveries table has all required columns: id, webhook_id, session_id, payload, target_url, signature, status, attempt_count, last_attempted_at, next_retry_at, created_at, error_detail.
- [ ] `mix test test/observatory/gateway/webhook_deliveries_test.exs` passes a test that verifies the webhook_configs table exists and maps source_identifier and event_type columns to agent_intent and target_session.
- [ ] `mix test test/observatory/gateway/webhook_deliveries_test.exs` passes a test that verifies a compound index exists on the webhook_deliveries table covering the status and next_retry_at columns.
- [ ] `mix compile --warnings-as-errors` passes with no warnings.

## Data
**Inputs:** Inbound webhook event with `source_identifier`, `event_type`, `session_id`, and serialized JSON payload.
**Outputs:** `webhook_deliveries` row with `status: "pending"` and `next_retry_at` set 30 seconds in the future.
**State changes:** New row inserted into `webhook_deliveries`; `webhook_configs` is read-only during delivery creation.

## Traceability
- Parent FR: FR-10.8
- ADR: [ADR-020](../../decisions/ADR-020-webhook-retry-dlq.md)
