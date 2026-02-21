---
id: FRD-010
title: Gateway Lifecycle Functional Requirements
date: 2026-02-22
status: draft
source_adr: [ADR-019, ADR-020]
related_rule: []
---

# FRD-010: Gateway Lifecycle

## Purpose

The Gateway Lifecycle subsystem manages the moment-to-moment operational state of every agent connected to the Observatory network. It encompasses three distinct mechanisms: a HeartbeatManager that tracks agent liveness and evicts stale entries from the Capability Map, a CronScheduler that fires timed jobs and accepts agent-requested one-time reminders, and a WebhookRouter that delivers inbound and outbound webhook payloads with durable exponential-backoff retry semantics.

These three mechanisms share a common design principle: each is a GenServer-backed module that operates independently but writes audit data to SQLite, communicates completion events over PubSub, and exposes HTTP endpoints for external callers. Together they ensure that the Gateway can survive process restarts without losing delivery state, can shed dead agents without operator intervention, and can guarantee at-least-once webhook delivery within a defined retry envelope.

## Functional Requirements

### FR-10.1: HeartbeatManager Module and Public API

The HeartbeatManager MUST be implemented as a GenServer at `lib/observatory/gateway/heartbeat_manager.ex` under the module `Observatory.Gateway.HeartbeatManager`. The module MUST expose a public function `HeartbeatManager.record_heartbeat(agent_id, cluster_id)` that updates the GenServer's in-memory state map with the entry `%{last_seen: DateTime.utc_now(), cluster_id: cluster_id}` keyed by `agent_id`. The function MUST return `:ok` synchronously. The GenServer's state MUST be a map with atom or string keys of the form `%{agent_id => %{last_seen: datetime, cluster_id: string}}`. In Phase 1, the GenServer MUST run as a single named process registered as `Observatory.Gateway.HeartbeatManager`. The public function signature MUST NOT change in Phase 2 when the leader-election wrapper is introduced.

**Positive path**: An agent calls `POST /gateway/heartbeat`; the controller calls `HeartbeatManager.record_heartbeat("agent-42", "cluster-west")`, which returns `:ok`. The GenServer state map now contains `"agent-42" => %{last_seen: ~U[...], cluster_id: "cluster-west"}`.

**Negative path**: If the GenServer process is not running when `record_heartbeat/2` is called, the call raises a `GenServer` exit. The HTTP controller MUST rescue this and return HTTP 503 `{"status": "error", "reason": "heartbeat_manager_unavailable"}` rather than crashing the request process.

---

### FR-10.2: Heartbeat Check Interval and Eviction Threshold

The HeartbeatManager MUST schedule a self-sent `:check_heartbeats` message every 30 seconds using `:timer.send_interval/2` or equivalent. On each check, the manager MUST iterate every entry in the state map and compare `last_seen` against `DateTime.utc_now()`. Any agent whose `last_seen` is more than 90 seconds in the past MUST be evicted: the entry MUST be removed from the state map and the manager MUST call `Observatory.Gateway.CapabilityMap.remove_agent(agent_id)` to remove the agent's capabilities from the live Capability Map. Evictions MUST be logged at the `:info` level with fields `agent_id` and `last_seen` so operators can audit liveness gaps.

**Positive path**: Agent "agent-99" last sent a heartbeat at T=0. At T=91 seconds the check fires, finds `last_seen` is 91 seconds ago (greater than the 90-second threshold), removes "agent-99" from the state map, and calls `CapabilityMap.remove_agent("agent-99")`.

**Negative path**: If the 90-second threshold is not configured as a module constant and the check loop uses a hardcoded literal in two places, a future threshold change becomes error-prone. The module MUST define `@eviction_threshold_seconds 90` and `@check_interval_ms 30_000` as module attributes and reference only those attributes in the loop and interval setup.

---

### FR-10.3: POST /gateway/heartbeat Endpoint

The Gateway MUST expose the HTTP endpoint `POST /gateway/heartbeat` that accepts a JSON body with the shape `%{"type" => "heartbeat", "agent_id" => string, "cluster_id" => string, "timestamp" => iso-8601-utc-string}`. The endpoint MUST validate that `agent_id` and `cluster_id` are non-empty strings and that `type` equals `"heartbeat"`. On successful validation, the endpoint MUST call `HeartbeatManager.record_heartbeat(agent_id, cluster_id)` and MUST upsert a row in the `gateway_heartbeats` SQLite table via `Ecto.Repo.insert/2` with `on_conflict: :replace_all, conflict_target: :agent_id`. The endpoint MUST return HTTP 200 `{"status": "ok"}` on success. The `timestamp` field from the body MUST be parsed and stored in the `last_seen_at` column; if parsing fails the field MUST fall back to `DateTime.utc_now()`.

**Positive path**: A well-formed heartbeat POST with `agent_id: "agent-42"` returns HTTP 200. The `gateway_heartbeats` row for `"agent-42"` now has `last_seen_at` equal to the parsed `timestamp` value. The HeartbeatManager in-memory state is also updated.

**Negative path**: A POST with `"type": "status_update"` instead of `"heartbeat"` MUST return HTTP 422 `{"status": "error", "reason": "invalid_heartbeat_type"}` without touching the HeartbeatManager or the database.

---

### FR-10.4: gateway_heartbeats SQLite Table

The SQLite database MUST contain a table named `gateway_heartbeats` with the following columns: `agent_id` (text, primary key), `cluster_id` (text, not null), and `last_seen_at` (datetime, not null). No additional columns are required in Phase 1. The table MUST be created via an Ecto migration. Rows MUST be upserted (not inserted) on each heartbeat receipt so that the table always reflects the most recent heartbeat per agent. The table MUST NOT accumulate one row per heartbeat event; it stores the current liveness snapshot only. Evicted agents MUST NOT have their rows deleted automatically; row cleanup is an operator responsibility in Phase 1.

**Positive path**: After 100 heartbeat POSTs from "agent-42", the `gateway_heartbeats` table contains exactly one row for `"agent-42"` with `last_seen_at` equal to the timestamp from the most recent POST.

**Negative path**: If the Ecto migration for `gateway_heartbeats` is absent, `mix compile --warnings-as-errors` will pass but the first heartbeat POST will raise `Ecto.QueryError`. The migration MUST be present before the module is deployed. CI MUST run `mix ecto.migrate` before integration tests.

---

### FR-10.5: CronScheduler Module and schedule_once/3 API

The CronScheduler MUST be implemented as a GenServer at `lib/observatory/gateway/cron_scheduler.ex` under the module `Observatory.Gateway.CronScheduler`. On startup, the GenServer MUST read all rows from the `cron_jobs` SQLite table and schedule recurring jobs using `Process.send_after/3` or a compatible mechanism. The module MUST expose a public function `CronScheduler.schedule_once(agent_id, delay_ms, payload)` that registers a one-time job to fire after `delay_ms` milliseconds. When the timer fires, the scheduler MUST broadcast the payload on the PubSub topic `"agent:#{agent_id}:scheduled"` using `Phoenix.PubSub.broadcast/3`. In Phase 1, the CronScheduler MUST run as a single named process registered as `Observatory.Gateway.CronScheduler`.

**Positive path**: `CronScheduler.schedule_once("agent-7", 5_000, %{reminder: "check_quota"})` registers a timer. Five seconds later the scheduler broadcasts `%{reminder: "check_quota"}` on `"agent:agent-7:scheduled"`. Any LiveView or process subscribed to that topic receives the message.

**Negative path**: If `delay_ms` is negative or zero, `schedule_once/3` MUST return `{:error, :invalid_delay}` without registering a timer. A negative delay passed to `Process.send_after/3` would cause a runtime error; the guard MUST reject it before that call.

---

### FR-10.6: cron_jobs SQLite Table

The SQLite database MUST contain a table named `cron_jobs` with the following columns: `id` (integer primary key autoincrement), `agent_id` (text, not null), `schedule` (text, nullable — cron expression for recurring jobs), `next_fire_at` (datetime, not null), `payload` (text, JSON-encoded, not null), and `is_one_time` (boolean, not null, default false). The CronScheduler MUST write one-time jobs created via `schedule_once/3` to this table with `is_one_time: true` and a computed `next_fire_at`. After a one-time job fires, its row MUST be deleted from `cron_jobs`. Recurring jobs (is_one_time: false) MUST have their `next_fire_at` updated after each firing; they MUST NOT be deleted.

**Positive path**: A call to `schedule_once("agent-7", 5_000, %{reminder: "check_quota"})` inserts a row with `is_one_time: true` and `next_fire_at` approximately 5 seconds in the future. After the job fires, the row is deleted. The table contains no orphaned one-time job rows for "agent-7".

**Negative path**: If a process crash occurs between job firing and row deletion, the row remains on disk with `is_one_time: true`. On next startup the CronScheduler reads it, sees `next_fire_at` is in the past, fires the job immediately, then deletes the row. This prevents silent job loss across restarts.

---

### FR-10.7: Agent-Requested Scheduling via schedule_reminder Tool Call

The SchemaInterceptor MUST inspect validated DecisionLog structs for the condition `action.tool_call == "schedule_reminder"`. When this condition is true, the SchemaInterceptor MUST extract `action.tool_input` and read the keys `delay_ms` (integer) and `payload` (map). It MUST then call `CronScheduler.schedule_once(decision_log.identity.agent_id, delay_ms, payload)` before forwarding the DecisionLog on its normal PubSub broadcast path. If `delay_ms` is absent or not a positive integer in `tool_input`, the SchemaInterceptor MUST emit a `:warning` log and skip the `schedule_once` call without rejecting the DecisionLog. The DecisionLog itself MUST still be forwarded regardless of whether the scheduling call succeeds.

**Positive path**: An agent submits a DecisionLog with `action.tool_call: "schedule_reminder"` and `action.tool_input: %{"delay_ms" => 60_000, "payload" => %{"task" => "check_quota"}}`. The SchemaInterceptor calls `CronScheduler.schedule_once(agent_id, 60_000, %{"task" => "check_quota"})` and then broadcasts the DecisionLog as usual. Sixty seconds later the scheduler fires the reminder.

**Negative path**: An agent submits a DecisionLog with `action.tool_call: "schedule_reminder"` but `action.tool_input: %{"delay_ms" => -500}`. The SchemaInterceptor logs a warning `"invalid delay_ms for schedule_reminder: -500"` and skips the `schedule_once` call. The DecisionLog is still broadcast on PubSub. No HTTP error is returned to the agent.

---

### FR-10.8: webhook_deliveries SQLite Table Structure

The SQLite database MUST contain a table named `webhook_deliveries` with the following columns: `id` (integer primary key autoincrement), `webhook_id` (integer, references `webhook_configs.id`, not null), `session_id` (text, not null), `payload` (text, JSON-encoded, not null), `target_url` (text, not null), `signature` (text, not null — HMAC-SHA256 hex digest), `status` (text, not null — one of `pending`, `delivered`, `failed`, `dead`), `attempt_count` (integer, not null, default 0), `last_attempted_at` (datetime, nullable), `next_retry_at` (datetime, nullable), `created_at` (datetime, not null), and `error_detail` (text, nullable). The table MUST also have an index on `status` and `next_retry_at` together so the periodic retry poll can efficiently find due entries. A companion table `webhook_configs` MUST map `{source_identifier, event_type}` pairs to `{agent_intent, target_session}`.

**Positive path**: A new inbound webhook event creates a `webhook_deliveries` row with `status: "pending"`, `attempt_count: 0`, and `next_retry_at` set to 30 seconds from `created_at`. The indexed query `WHERE status IN ('pending','failed') AND next_retry_at <= now()` finds the row on the first poll cycle.

**Negative path**: If the compound index on `(status, next_retry_at)` is absent, the periodic poll performs a full table scan. While functionally correct, this violates the zero-warnings policy only if SQLite query analysis surfaced it. The migration MUST include the index to ensure efficient operation at scale.

---

### FR-10.9: Exponential Backoff Retry Schedule

The WebhookRouter MUST implement exponential backoff with the following exact retry schedule after each failed delivery attempt: attempt 1 retries after 30 seconds, attempt 2 retries after 2 minutes, attempt 3 retries after 10 minutes, attempt 4 retries after 1 hour, attempt 5 retries after 6 hours. After attempt 5 fails (attempt_count reaches 6 with no success), the WebhookRouter MUST set `status: "dead"` on the `webhook_deliveries` row and MUST emit a `WebhookDLQEvent` via `Phoenix.PubSub.broadcast/3` on the `"gateway:webhooks"` topic. No further automatic retry attempts MUST occur for a dead entry. The `next_retry_at` computation MUST use `DateTime.add(DateTime.utc_now(), delay_seconds, :second)` and MUST be persisted to the database before the current process releases the row.

**Positive path**: A delivery fails on attempt 1. The row is updated with `attempt_count: 1`, `status: "failed"`, and `next_retry_at` set to 30 seconds from now. After attempt 5 fails, `attempt_count` is 5, `status` becomes `"dead"`, and a `WebhookDLQEvent` is broadcast. No further retries occur automatically.

**Negative path**: If the retry schedule is implemented as a runtime arithmetic formula rather than an explicit lookup, a formula error could produce a negative `next_retry_at`. The module MUST define the schedule as a module-level list `@retry_schedule_seconds [30, 120, 600, 3600, 21600]` and look up `Enum.at(@retry_schedule_seconds, attempt_count)` to prevent arithmetic drift.

---

### FR-10.10: HMAC-SHA256 Outbound Signature and Inbound Validation

Every outbound webhook delivery MUST include the HTTP request header `X-Observatory-Signature: sha256={hmac_hex_digest}`, where the digest is HMAC-SHA256 of the JSON-encoded payload using a shared secret stored in the corresponding `webhook_configs` row. The WebhookRouter MUST compute this signature using `:crypto.mac(:hmac, :sha256, secret, payload_json)` and hex-encode the result. For inbound webhooks received at `POST /gateway/webhooks/:webhook_id`, the controller MUST validate the `X-Observatory-Signature` header against a recomputed digest using `Plug.Crypto.secure_compare/2` to prevent timing attacks. A mismatch MUST return HTTP 401 and MUST emit a `WebhookSignatureFailureEvent` on `"gateway:webhooks"` PubSub topic. A valid signature MUST allow the request to proceed to routing logic.

**Positive path**: An external service sends a POST to `/gateway/webhooks/7` with header `X-Observatory-Signature: sha256=abcdef...`. The controller computes the expected digest from the request body and the stored secret for webhook 7. `Plug.Crypto.secure_compare/2` returns true. The request proceeds to routing. A `webhook_deliveries` row is created with `status: "pending"`.

**Negative path**: The same POST arrives with a tampered body. The recomputed digest does not match the header value. `secure_compare/2` returns false. The controller returns HTTP 401 `{"status": "error", "reason": "signature_mismatch"}` and broadcasts a `WebhookSignatureFailureEvent` with `webhook_id: 7` on `"gateway:webhooks"`.

---

### FR-10.11: Startup Durability — Re-Queue Undelivered Entries

On GenServer initialization, the WebhookRouter MUST query the `webhook_deliveries` table for all rows with `status IN ("pending", "failed")` and re-schedule them for delivery. For each re-queued row, the WebhookRouter MUST compare `next_retry_at` against `DateTime.utc_now()`: if `next_retry_at` is in the past, the row MUST be dispatched immediately (within the first poll cycle); if `next_retry_at` is in the future, it MUST remain queued until that time. This behavior ensures that a process restart does not silently drop in-flight deliveries. The WebhookRouter MUST NOT re-queue rows with `status: "dead"` on startup; dead entries require explicit operator intervention.

**Positive path**: The GenServer crashes and restarts. On `init/1`, it queries `webhook_deliveries` and finds three rows with `status: "failed"` and `next_retry_at` values in the past. All three are dispatched in the first poll cycle, within 30 seconds of startup.

**Negative path**: If the startup re-queue step is absent and the GenServer holds retry timers only in process memory, a crash loses all pending timers. Webhook deliveries silently stall until an operator manually resets rows to `"pending"`. The startup query is mandatory for durability.

---

### FR-10.12: Thundering-Herd Prevention and gateway:webhooks PubSub Topic

The WebhookRouter periodic poll MUST NOT dispatch more than 5 outbound HTTP requests per second. The poll interval MUST be configurable via a module attribute `@poll_interval_ms` defaulting to 5_000 (5 seconds). When the poll finds more than 5 due entries, it MUST process at most 5 per cycle, leaving the remainder for subsequent cycles. All delivery status change events and `WebhookDLQEvent` emissions MUST be broadcast on the PubSub topic `"gateway:webhooks"` using `Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:webhooks", event)`. Operators MAY reset a `"dead"` entry to `"pending"` via a UI "Retry now" action, which MUST set `attempt_count: 0` and `status: "pending"` so that the full 6-attempt retry envelope is available again.

**Positive path**: A poll finds 12 due `webhook_deliveries` rows. The router dispatches exactly 5 HTTP requests in this cycle. The remaining 7 rows are left untouched. On the next poll cycle, 5 more are dispatched. No more than 5 outbound connections are opened per poll. A `WebhookDLQEvent` for a dead entry is broadcast on `"gateway:webhooks"` and received by any subscribed LiveView.

**Negative path**: If the per-cycle cap is not enforced and 200 rows become due simultaneously (e.g., after a long outage), the poll dispatches 200 concurrent HTTP requests. This saturates the connection pool. The 5-per-cycle cap MUST be enforced unconditionally, even during catch-up after a restart.

---

## Out of Scope (Phase 1)

- Redis SETNX leader election for HeartbeatManager (Phase 2 migration path only)
- Distributed CronScheduler with raft-based consensus for job deduplication
- Webhook payload encryption at rest in the webhook_deliveries table
- Webhook delivery rate limiting per target_url (beyond thundering-herd cap)
- Automatic row deletion for evicted agents in gateway_heartbeats
- OAuth-based authentication for webhook endpoint callers

## Related ADRs

- [ADR-019](../../decisions/ADR-019-heartbeat-leader-election.md) -- Defines HeartbeatManager design, eviction threshold, check interval, CronScheduler public API, and agent-requested scheduling via schedule_reminder tool_call
- [ADR-020](../../decisions/ADR-020-webhook-retry-dlq.md) -- Defines WebhookRouter module, webhook_deliveries table schema, exponential backoff schedule, HMAC-SHA256 signature requirements, startup durability, and thundering-herd prevention
