---
id: ADR-020
title: Webhook Reliability: Retry + DLQ
date: 2026-02-21
status: proposed
related_tasks: []
parent: ADR-013
superseded_by: null
---
# ADR-020 Webhook Reliability: Retry + DLQ
[2026-02-21] proposed

## Related ADRs
- [ADR-013](ADR-013-hypervisor-platform-scope.md) Hypervisor Platform Scope (parent)
- [ADR-019](ADR-019-heartbeat-leader-election.md) Heartbeat and Leader Election

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief §4.1 | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | Webhook reliability: retry + exponential backoff + DLQ |

## Context

The Gateway emits outbound webhooks when autonomous tasks complete (callback to pre-configured URLs). Webhooks are "fire and forget" by nature — the recipient server may be down, slow, or returning 5xx. Without retry logic, completed tasks silently fail to notify their callers.

The project brief requires: "Retry with Exponential Backoff and a Dead Letter Queue (DLQ) for failed deliveries."

For inbound webhooks, the Gateway must validate signatures before routing to agent intents.

## Options Considered

**Retry mechanism:**

1. **In-process GenServer queue** — `WebhookRouter` GenServer holds a queue of pending deliveries. On failure, schedules a retry with `Process.send_after`. Queue is ephemeral (lost on crash).
   - Con: Gateway restart loses all pending retries. Not durable.

2. **SQLite-backed delivery queue** — Each outbound webhook delivery attempt is recorded in SQLite. On startup, the GenServer reads undelivered entries and retries them.
   - Pro: Durable across restarts. Simple with existing SQLite infrastructure.
   - Con: SQLite contention if webhook volume is high (>100/s). Acceptable for current scale.

3. **External queue (NATS JetStream or Redis Streams)** — Durable message queue as infrastructure dependency.
   - Pro: Purpose-built durability. High throughput.
   - Con: Adds infrastructure dependency. Disproportionate for v1 webhook volume.

**DLQ implementation:**

A. **Same SQLite table with status field** — Failed deliveries that exceed max retries get `status = "dead"`. UI queries dead entries via Forensic Inspector.
B. **Separate DLQ table** — Cleaner separation but more schema complexity.

## Decision

**Option 2 + Option A** — SQLite-backed delivery queue with DLQ status in the same table.

**Delivery table schema:**
```sql
CREATE TABLE webhook_deliveries (
  id INTEGER PRIMARY KEY,
  webhook_id TEXT NOT NULL,           -- references webhook_configs.id
  session_id TEXT,
  payload TEXT NOT NULL,              -- JSON
  target_url TEXT NOT NULL,
  signature TEXT NOT NULL,            -- HMAC-SHA256 of payload
  status TEXT DEFAULT 'pending',      -- pending | delivered | failed | dead
  attempt_count INTEGER DEFAULT 0,
  last_attempted_at DATETIME,
  next_retry_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  error_detail TEXT                   -- last error message
);
```

**Retry schedule (exponential backoff):**

| Attempt | Delay |
|---------|-------|
| 1 | 30 seconds |
| 2 | 2 minutes |
| 3 | 10 minutes |
| 4 | 1 hour |
| 5 | 6 hours |
| 6+ | Dead (moved to DLQ status) |

**Delivery attempt flow:**
1. `WebhookRouter.deliver/1` posts to target URL with `X-Observatory-Signature: sha256={hmac}` header
2. HTTP 2xx → update status to `"delivered"`, clear `next_retry_at`
3. Non-2xx or connection error → increment `attempt_count`, compute next delay, update `next_retry_at`
4. If `attempt_count >= 6` → set status to `"dead"`, emit `WebhookDLQEvent` to PubSub `"gateway:webhooks"`

**Inbound webhook validation:**
```elixir
# lib/observatory/gateway/webhook_router.ex
defp validate_signature(payload, signature, secret) do
  expected = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  Plug.Crypto.secure_compare("sha256=#{expected}", signature)
end
```

Inbound webhooks that fail signature validation receive HTTP 401; a `WebhookSignatureFailureEvent` is emitted.

**Inbound routing:** A `webhook_configs` table maps `{source_identifier, event_type}` → `{agent_intent, target_session}`. For example: `{source: "github", event_type: "pull_request.opened"}` → `{intent: "code_review", cluster: "reviewer-cluster"}`.

**Forensic Inspector:** Queries webhook_deliveries table by session_id, status, or date range. Shows DLQ entries with retry history and error details. "Retry now" button resets `attempt_count` and `status` to `"pending"`.

## Rationale

SQLite is the right call for v1 webhook volume. The existing project uses SQLite for events; adding webhook_deliveries is consistent. The exponential backoff schedule (30s → 2m → 10m → 1h → 6h → dead) matches standard webhook retry conventions used by Stripe, GitHub, and Segment.

The HMAC-SHA256 signature (outbound and inbound validation) is the industry standard. It is stateless and requires no external service.

## Consequences

- New module: `lib/observatory/gateway/webhook_router.ex`
- New GenServer: periodic check for `next_retry_at < now` entries, max 5 retries/s to avoid thundering herd
- New SQLite migration: `webhook_deliveries` table + `webhook_configs` table
- New HTTP endpoint: `POST /gateway/webhooks/:webhook_id` — inbound webhook receiver
- New PubSub topic: `"gateway:webhooks"` — DLQ events + delivery status changes
- Forensic Inspector (ADR-022 View 5) gains "Webhooks" panel reading from webhook_deliveries
- Scheduler & Lifecycle (View 4) DLQ panel reads from webhook_deliveries where status = 'dead'
