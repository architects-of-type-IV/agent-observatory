---
type: phase
id: 4
title: gateway-infrastructure-and-hitl
date: 2026-02-22
status: pending
links:
  adr: [ADR-019, ADR-020, ADR-021]
depends_on:
  - phase: 2
---

# Phase 4: Gateway Infrastructure & HITL

## Overview

This phase implements the three time-driven lifecycle services that govern ongoing agent operation — a `HeartbeatManager` GenServer that tracks agent liveness and evicts stale entries from the Capability Map, a `CronScheduler` GenServer that fires timed jobs and accepts agent-requested one-time reminders, and a `WebhookRouter` GenServer that delivers outbound webhook payloads with durable exponential-backoff retry semantics and validates inbound webhook signatures using HMAC-SHA256. Each of these services is backed by a SQLite table for durability across process restarts, communicates completion events over PubSub, and exposes at least one HTTP endpoint for external callers. Together they ensure the Gateway can survive process crashes without losing delivery state, shed dead agents without operator intervention, and guarantee at-least-once webhook delivery within a defined retry envelope.

The second half of this phase introduces the Human-in-the-Loop Intervention API, implemented as the `HITLRelay` GenServer. The relay owns a per-session two-state machine (`Normal` / `Paused`), buffers incoming DecisionLog messages in an ETS table while a session is paused, and flushes the buffer in arrival order (with any operator rewrites applied) when the session is unpaused. Operator interventions are delivered over four authenticated HTTP endpoints and are persisted as `HITLInterventionEvent` Ash resource rows for full audit traceability. The `SchemaInterceptor` from Phase 2 is extended to auto-pause sessions when `control.hitl_required == true` is set on an incoming DecisionLog, ensuring the agent cannot proceed until an operator explicitly approves, rewrites, or rejects the pending action.

### ADR Links
- [ADR-019](../decisions/ADR-019-heartbeat-leader-election.md) — Heartbeat and Leader Election for Gateway
- [ADR-020](../decisions/ADR-020-webhook-retry-dlq.md) — Webhook Reliability: Retry + DLQ
- [ADR-021](../decisions/ADR-021-hitl-intervention-api.md) — HITL Manual Intervention API

---

## 4.1 HeartbeatManager GenServer

- [ ] **Section 4.1 Complete**

This section creates the `Observatory.Gateway.HeartbeatManager` GenServer, defines its public API (`record_heartbeat/2`), wires the 30-second self-check loop with a 90-second eviction threshold, creates the `gateway_heartbeats` SQLite table migration, and implements the `POST /gateway/heartbeat` HTTP endpoint. By the end of this section, agents can ping the gateway to register their liveness and stale agents are automatically removed from both the in-memory state map and the live Capability Map without operator intervention.

### 4.1.1 GenServer Module and State Map

- [ ] **Task 4.1.1 Complete**
- **Governed by:** ADR-019
- **Parent UCs:** UC-0260, UC-0261

Create `lib/observatory/gateway/heartbeat_manager.ex` under the module `Observatory.Gateway.HeartbeatManager`. The module must define the GenServer, declare `@eviction_threshold_seconds 90` and `@check_interval_ms 30_000` as module attributes, and expose a synchronous public function `record_heartbeat(agent_id, cluster_id)` that returns `:ok`. The GenServer state must be a map of the form `%{agent_id => %{last_seen: DateTime.t(), cluster_id: String.t()}}`. On `init/1`, the module must start the 30-second check timer using `:timer.send_interval(@check_interval_ms, :check_heartbeats)`.

- [ ] 4.1.1.1 Create `lib/observatory/gateway/heartbeat_manager.ex` with `use GenServer`, declare `@eviction_threshold_seconds 90` and `@check_interval_ms 30_000`, add `def start_link/1` that registers the process as `__MODULE__`, and implement `init/1` that calls `:timer.send_interval(@check_interval_ms, :check_heartbeats)` and returns `{:ok, %{}}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.1.1.2 Implement `def record_heartbeat(agent_id, cluster_id)` as `GenServer.call(__MODULE__, {:heartbeat, agent_id, cluster_id})` and the corresponding `handle_call/3` that inserts or replaces `agent_id => %{last_seen: DateTime.utc_now(), cluster_id: cluster_id}` in the state map and returns `{:reply, :ok, updated_state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.1.1.3 Implement `handle_info(:check_heartbeats, state)` that calls `DateTime.utc_now()`, iterates every entry in state via `Enum.filter/2`, evicts agents where `DateTime.diff(now, last_seen, :second) > @eviction_threshold_seconds`, calls `Observatory.Gateway.CapabilityMap.remove_agent(agent_id)` for each evicted entry, logs each eviction at `:info` level with `agent_id` and `last_seen` fields, and returns `{:noreply, Map.drop(state, evicted_agent_ids)}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.1.1.4 Add `Observatory.Gateway.HeartbeatManager` to the application supervisor in `lib/observatory/application.ex` under the Gateway children group `done_when: "mix compile --warnings-as-errors"`

### 4.1.2 gateway_heartbeats Migration and Ecto Schema

- [ ] **Task 4.1.2 Complete**
- **Governed by:** ADR-019
- **Parent UCs:** UC-0263

Create the Ecto migration that establishes the `gateway_heartbeats` table with the required columns and define the companion Ecto schema module for performing upserts. The table stores exactly one row per agent reflecting the most recent heartbeat; repeated heartbeats upsert via `on_conflict: :replace_all, conflict_target: :agent_id`. No row cleanup is performed automatically on eviction in Phase 1.

- [ ] 4.1.2.1 Generate and populate an Ecto migration in `priv/repo/migrations/` that creates table `gateway_heartbeats` with columns: `agent_id text primary key`, `cluster_id text not null`, `last_seen_at datetime not null` `done_when: "mix ecto.migrate && mix compile --warnings-as-errors"`
- [ ] 4.1.2.2 Create `lib/observatory/gateway/heartbeat_record.ex` under module `Observatory.Gateway.HeartbeatRecord` using `use Ecto.Schema`, define `schema "gateway_heartbeats" do` with `field :agent_id, :string`, `field :cluster_id, :string`, `field :last_seen_at, :utc_datetime`, and implement a `changeset/2` that casts and validates presence of all three fields `done_when: "mix compile --warnings-as-errors"`

### 4.1.3 POST /gateway/heartbeat Controller

- [ ] **Task 4.1.3 Complete**
- **Governed by:** ADR-019
- **Parent UCs:** UC-0260, UC-0262

Implement the Phoenix controller action and router entry for `POST /gateway/heartbeat`. The action must validate that the request body contains `type == "heartbeat"`, non-empty `agent_id`, and non-empty `cluster_id`; parse the optional `timestamp` field (falling back to `DateTime.utc_now()` on parse failure); upsert the `HeartbeatRecord` via `Repo.insert/2` with `on_conflict: :replace_all, conflict_target: :agent_id`; and then call `HeartbeatManager.record_heartbeat/2`. The controller must rescue `GenServer` exits from a downed `HeartbeatManager` and return HTTP 503.

- [ ] 4.1.3.1 Create `lib/observatory_web/controllers/heartbeat_controller.ex` under module `ObservatoryWeb.HeartbeatController` with `def create(conn, params)` that pattern-matches on `params["type"] == "heartbeat"` and non-empty `agent_id` and `cluster_id` strings, returns HTTP 422 `{"status": "error", "reason": "invalid_heartbeat_type"}` when `type` is wrong, and returns HTTP 422 `{"status": "error", "reason": "missing_required_fields"}` when either id field is absent or empty `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.1.3.2 On the success path in `HeartbeatController.create/2`, parse `params["timestamp"]` via `DateTime.from_iso8601/1` falling back to `DateTime.utc_now()`, build a `HeartbeatRecord` changeset, call `Repo.insert(changeset, on_conflict: :replace_all, conflict_target: :agent_id)`, then call `HeartbeatManager.record_heartbeat(agent_id, cluster_id)` in a `try/rescue` block that catches `GenServer` exits and returns `json(conn |> put_status(503), %{status: "error", reason: "heartbeat_manager_unavailable"})` on failure; return `json(conn, %{status: "ok"})` on full success `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.1.3.3 Add `post "/gateway/heartbeat", HeartbeatController, :create` to `lib/observatory_web/router.ex` in the `:api` pipeline scope `done_when: "mix compile --warnings-as-errors"`

### 4.1.4 HeartbeatManager Tests

- [ ] **Task 4.1.4 Complete**
- **Governed by:** ADR-019
- **Parent UCs:** UC-0260, UC-0261, UC-0262, UC-0263

Write ExUnit tests covering the GenServer public API, eviction loop, and HTTP endpoint behaviour under valid, invalid, and edge-case inputs.

- [ ] 4.1.4.1 Create `test/observatory/gateway/heartbeat_manager_test.exs` and write tests verifying: (a) `HeartbeatManager.record_heartbeat("agent-1", "cluster-a")` returns `:ok`; (b) a second call with the same `agent_id` replaces the entry rather than creating a duplicate; (c) calling `record_heartbeat/2` when the GenServer is not running raises a `GenServer` exit `done_when: "mix test test/observatory/gateway/heartbeat_manager_test.exs"`
- [ ] 4.1.4.2 In `test/observatory/gateway/heartbeat_manager_test.exs`, write a test that starts an isolated `HeartbeatManager` process, records a heartbeat, manipulates the process state to set `last_seen` to `DateTime.add(DateTime.utc_now(), -100, :second)`, sends `:check_heartbeats` directly, and asserts `CapabilityMap.remove_agent/1` was called (via a mock or process message assertion) `done_when: "mix test test/observatory/gateway/heartbeat_manager_test.exs"`
- [ ] 4.1.4.3 Create `test/observatory_web/controllers/heartbeat_controller_test.exs` and write tests verifying: (a) a valid POST returns HTTP 200 `{"status": "ok"}`; (b) a POST with `type: "status_update"` returns HTTP 422 with `reason: "invalid_heartbeat_type"`; (c) a POST missing `agent_id` returns HTTP 422; (d) the `gateway_heartbeats` table contains exactly one row for the agent after two identical POSTs `done_when: "mix test test/observatory_web/controllers/heartbeat_controller_test.exs"`

---

## 4.2 CronScheduler & DB Schema

- [ ] **Section 4.2 Complete**

This section implements the `Observatory.Gateway.CronScheduler` GenServer with its `schedule_once/3` public API, creates the `cron_jobs` SQLite table migration, implements startup recovery for unfinished jobs, and wires the SchemaInterceptor extension that translates `schedule_reminder` tool calls into `CronScheduler.schedule_once/3` invocations. By the end of this section, agents can request timed reminders via DecisionLog tool calls, and the scheduler survives process crashes without silently dropping pending one-time jobs.

### 4.2.1 CronScheduler GenServer Module

- [ ] **Task 4.2.1 Complete**
- **Governed by:** ADR-019
- **Parent UCs:** UC-0264, UC-0265

Create `lib/observatory/gateway/cron_scheduler.ex` under the module `Observatory.Gateway.CronScheduler`. The GenServer must read all rows from the `cron_jobs` table in `init/1` and schedule timers for every unfinished job. It must expose `schedule_once(agent_id, delay_ms, payload)` that validates `delay_ms` is a positive integer, inserts a `cron_jobs` row with `is_one_time: true`, and registers a timer via `Process.send_after/3`. When a timer fires, the scheduler must broadcast the payload on `"agent:#{agent_id}:scheduled"` via `Phoenix.PubSub.broadcast/3` and delete the corresponding `cron_jobs` row (for one-time jobs).

- [ ] 4.2.1.1 Create `lib/observatory/gateway/cron_scheduler.ex` with `use GenServer`, implement `start_link/1` that registers as `__MODULE__`, and implement `init/1` that queries all `cron_jobs` rows from the Repo, schedules timers for each using `Process.send_after(self(), {:fire_job, row.id, row.agent_id, row.payload}, max(delay_until_fire, 0))` where `delay_until_fire` is computed as `DateTime.diff(row.next_fire_at, DateTime.utc_now(), :millisecond)`, and returns `{:ok, %{jobs: %{}}}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.2.1.2 Implement `def schedule_once(agent_id, delay_ms, payload)` as a `GenServer.call` that returns `{:error, :invalid_delay}` when `delay_ms` is not a positive integer, otherwise inserts a `CronJob` Ecto record with `is_one_time: true`, `next_fire_at: DateTime.add(DateTime.utc_now(), delay_ms, :millisecond)`, and `payload: Jason.encode!(payload)`, then calls `Process.send_after/3` with the timer, and returns `:ok` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.2.1.3 Implement `handle_info({:fire_job, job_id, agent_id, payload_json}, state)` that decodes `payload_json` via `Jason.decode!/1`, calls `Phoenix.PubSub.broadcast(Observatory.PubSub, "agent:#{agent_id}:scheduled", decoded_payload)`, queries the `cron_jobs` row by `job_id`, and if `is_one_time: true` deletes the row from the Repo; for recurring jobs updates `next_fire_at` and re-schedules the timer; returns `{:noreply, state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.2.1.4 Add `Observatory.Gateway.CronScheduler` to the application supervisor in `lib/observatory/application.ex` `done_when: "mix compile --warnings-as-errors"`

### 4.2.2 cron_jobs Migration and Ecto Schema

- [ ] **Task 4.2.2 Complete**
- **Governed by:** ADR-019
- **Parent UCs:** UC-0264, UC-0265

Create the Ecto migration that defines the `cron_jobs` table and the companion Ecto schema module `Observatory.Gateway.CronJob`. The schema must model all columns including `is_one_time`, `next_fire_at`, and `payload` (JSON-encoded text). The changeset must validate that `payload` is present and `next_fire_at` is present.

- [ ] 4.2.2.1 Generate and populate an Ecto migration in `priv/repo/migrations/` that creates table `cron_jobs` with columns: `id integer primary key autoincrement`, `agent_id text not null`, `schedule text`, `next_fire_at datetime not null`, `payload text not null`, `is_one_time boolean not null default false` `done_when: "mix ecto.migrate && mix compile --warnings-as-errors"`
- [ ] 4.2.2.2 Create `lib/observatory/gateway/cron_job.ex` under module `Observatory.Gateway.CronJob` using `use Ecto.Schema`, define `schema "cron_jobs" do` with the five non-id columns, and implement `changeset/2` that casts all fields and validates presence of `agent_id`, `next_fire_at`, and `payload` `done_when: "mix compile --warnings-as-errors"`

### 4.2.3 SchemaInterceptor Extension for schedule_reminder

- [ ] **Task 4.2.3 Complete**
- **Governed by:** ADR-019
- **Parent UCs:** UC-0266

Extend the Phase 2 `SchemaInterceptor` module to detect `action.tool_call == "schedule_reminder"` on validated DecisionLog structs and call `CronScheduler.schedule_once/3` before forwarding the DecisionLog on PubSub. If `tool_input.delay_ms` is absent or not a positive integer, the interceptor must log a warning and skip the scheduling call. The DecisionLog must be forwarded regardless of scheduling outcome.

- [ ] 4.2.3.1 In `lib/observatory/gateway/schema_interceptor.ex`, add a private function `maybe_schedule_reminder/1` that receives a `%DecisionLog{}` struct, checks `log.action.tool_call == "schedule_reminder"`, extracts `delay_ms` and `payload` from `log.action.tool_input` (parsed from JSON string if needed), calls `CronScheduler.schedule_once(log.identity.agent_id, delay_ms, payload)` when `delay_ms` is a positive integer, and logs `Logger.warning("invalid delay_ms for schedule_reminder: #{inspect(delay_ms)}")` otherwise `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.2.3.2 Call `maybe_schedule_reminder(decision_log)` in the SchemaInterceptor's post-validation pipeline immediately before the existing `Phoenix.PubSub.broadcast/3` call that forwards the DecisionLog, ensuring the broadcast still occurs on both the success and warning paths `done_when: "mix compile --warnings-as-errors"`

### 4.2.4 CronScheduler Tests

- [ ] **Task 4.2.4 Complete**
- **Governed by:** ADR-019
- **Parent UCs:** UC-0264, UC-0265, UC-0266

Write ExUnit tests covering the `schedule_once/3` public API, startup recovery, invalid delay rejection, and the SchemaInterceptor extension.

- [ ] 4.2.4.1 Create `test/observatory/gateway/cron_scheduler_test.exs` and write tests verifying: (a) `CronScheduler.schedule_once("agent-7", 100, %{task: "check"})` returns `:ok` and a `cron_jobs` row is inserted with `is_one_time: true`; (b) after the timer fires, the PubSub topic `"agent:agent-7:scheduled"` receives `%{task: "check"}`; (c) after the timer fires, the `cron_jobs` row for the one-time job is deleted `done_when: "mix test test/observatory/gateway/cron_scheduler_test.exs"`
- [ ] 4.2.4.2 In `test/observatory/gateway/cron_scheduler_test.exs`, write tests verifying: (a) `CronScheduler.schedule_once("agent-7", 0, %{})` returns `{:error, :invalid_delay}`; (b) `CronScheduler.schedule_once("agent-7", -500, %{})` returns `{:error, :invalid_delay}`; (c) on startup with a `cron_jobs` row whose `next_fire_at` is in the past, the scheduler fires the job within the first poll cycle and then deletes the row `done_when: "mix test test/observatory/gateway/cron_scheduler_test.exs"`

---

## 4.3 WebhookRouter Retry & DLQ

- [ ] **Section 4.3 Complete**

This section creates the `Observatory.Gateway.WebhookRouter` GenServer that manages durable webhook delivery with exponential-backoff retry semantics, implements HMAC-SHA256 signature computation for outbound webhooks and timing-safe validation for inbound webhooks, creates the `webhook_deliveries` and `webhook_configs` SQLite migrations, implements startup re-queuing of undelivered entries, enforces the five-per-poll thundering-herd cap, and exposes `POST /gateway/webhooks/:webhook_id` for inbound webhook receipt. By the end of this section, the Gateway guarantees at-least-once delivery for outbound webhooks and cryptographically validates all inbound ones.

### 4.3.1 WebhookRouter GenServer and Retry Schedule

- [ ] **Task 4.3.1 Complete**
- **Governed by:** ADR-020
- **Parent UCs:** UC-0268, UC-0270

Create `lib/observatory/gateway/webhook_router.ex` under the module `Observatory.Gateway.WebhookRouter`. The GenServer must declare `@retry_schedule_seconds [30, 120, 600, 3600, 21600]` and `@poll_interval_ms 5_000` as module attributes. The periodic poll must query `webhook_deliveries` rows with `status IN ("pending", "failed") AND next_retry_at <= now()`, take at most 5 entries, attempt HTTP delivery for each, and update the row status based on the result. After five consecutive failures, the row is marked `status: "dead"` and a `WebhookDLQEvent` is broadcast.

- [ ] 4.3.1.1 Create `lib/observatory/gateway/webhook_router.ex` with `use GenServer`, declare `@retry_schedule_seconds [30, 120, 600, 3600, 21600]` and `@poll_interval_ms 5_000`, implement `start_link/1` registered as `__MODULE__`, implement `init/1` that calls startup re-queuing (calls private `requeue_undelivered/0`) and schedules the first poll via `Process.send_after(self(), :poll, @poll_interval_ms)`, returns `{:ok, %{}}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.3.1.2 Implement `handle_info(:poll, state)` that queries `Repo.all(from d in WebhookDelivery, where: d.status in ["pending", "failed"] and d.next_retry_at <= ^DateTime.utc_now(), limit: 5)`, calls `attempt_delivery/1` for each, re-schedules the next poll via `Process.send_after(self(), :poll, @poll_interval_ms)`, returns `{:noreply, state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.3.1.3 Implement private `attempt_delivery/1` that issues an HTTP POST to `delivery.target_url` with body `delivery.payload` and header `X-Observatory-Signature: sha256=#{delivery.signature}` using `Req.post/2` or `:httpc.request/4`; on HTTP 2xx calls `mark_delivered/1` to set `status: "delivered"`; on failure calls `schedule_retry/1` that increments `attempt_count`, looks up the delay via `Enum.at(@retry_schedule_seconds, delivery.attempt_count)`, sets `next_retry_at: DateTime.add(DateTime.utc_now(), delay, :second)` and `status: "failed"`, or if `attempt_count >= 5` sets `status: "dead"` and broadcasts `%WebhookDLQEvent{webhook_id: delivery.webhook_id}` on `"gateway:webhooks"` via `Phoenix.PubSub.broadcast/3` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.3.1.4 Implement private `requeue_undelivered/0` that queries all rows with `status IN ("pending", "failed")` on startup; for each row whose `next_retry_at` is in the past, updates `next_retry_at` to `DateTime.utc_now()` so the first poll cycle dispatches it immediately; leaves rows with future `next_retry_at` unchanged `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.3.1.5 Add `Observatory.Gateway.WebhookRouter` to the application supervisor in `lib/observatory/application.ex` `done_when: "mix compile --warnings-as-errors"`

### 4.3.2 webhook_deliveries and webhook_configs Migrations

- [ ] **Task 4.3.2 Complete**
- **Governed by:** ADR-020
- **Parent UCs:** UC-0279

Create the two Ecto migrations and the `Observatory.Gateway.WebhookDelivery` Ecto schema. The `webhook_deliveries` table must have a compound index on `(status, next_retry_at)` to support efficient polling. The companion `webhook_configs` table maps `{source_identifier, event_type}` pairs to `{agent_intent, target_session}`.

- [ ] 4.3.2.1 Generate and populate an Ecto migration in `priv/repo/migrations/` that creates table `webhook_configs` with columns: `id integer primary key autoincrement`, `source_identifier text not null`, `event_type text not null`, `agent_intent text not null`, `target_session text not null`, `secret text not null`; and creates table `webhook_deliveries` with columns: `id integer primary key autoincrement`, `webhook_id integer not null references webhook_configs(id)`, `session_id text not null`, `payload text not null`, `target_url text not null`, `signature text not null`, `status text not null default "pending"`, `attempt_count integer not null default 0`, `last_attempted_at datetime`, `next_retry_at datetime`, `created_at datetime not null`, `error_detail text` `done_when: "mix ecto.migrate && mix compile --warnings-as-errors"`
- [ ] 4.3.2.2 Add the compound index `CREATE INDEX idx_webhook_deliveries_status_retry ON webhook_deliveries (status, next_retry_at)` to the same migration `done_when: "mix ecto.migrate && mix compile --warnings-as-errors"`
- [ ] 4.3.2.3 Create `lib/observatory/gateway/webhook_delivery.ex` under module `Observatory.Gateway.WebhookDelivery` using `use Ecto.Schema`, define `schema "webhook_deliveries" do` with all eleven non-id columns using appropriate Ecto field types, and implement `changeset/2` that casts all fields and validates presence of `session_id`, `payload`, `target_url`, `signature`, and `status` `done_when: "mix compile --warnings-as-errors"`

### 4.3.3 HMAC-SHA256 Signature and Inbound Endpoint

- [ ] **Task 4.3.3 Complete**
- **Governed by:** ADR-020
- **Parent UCs:** UC-0267

Implement the inbound webhook endpoint `POST /gateway/webhooks/:webhook_id` and the HMAC-SHA256 signature validation logic. The endpoint must look up the `webhook_configs` row by `webhook_id`, compute the expected digest using `:crypto.mac(:hmac, :sha256, secret, payload_body)`, compare it against the `X-Observatory-Signature` header using `Plug.Crypto.secure_compare/2`, return HTTP 401 on mismatch with a `WebhookSignatureFailureEvent` broadcast, and create a `webhook_deliveries` row on success.

- [ ] 4.3.3.1 Create `lib/observatory_web/controllers/webhook_controller.ex` under module `ObservatoryWeb.WebhookController` with `def receive(conn, %{"webhook_id" => webhook_id})` that reads the raw request body, looks up the `webhook_configs` row, computes `expected = :crypto.mac(:hmac, :sha256, config.secret, raw_body) |> Base.encode16(case: :lower)`, compares `Plug.Crypto.secure_compare("sha256=#{expected}", header_sig)` where `header_sig` is from `conn |> get_req_header("x-observatory-signature") |> List.first()`, returns HTTP 401 `{"status": "error", "reason": "signature_mismatch"}` and broadcasts `%WebhookSignatureFailureEvent{webhook_id: webhook_id}` on `"gateway:webhooks"` on mismatch `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.3.3.2 On the success path in `WebhookController.receive/2`, insert a `WebhookDelivery` row with `status: "pending"`, `attempt_count: 0`, `next_retry_at: DateTime.add(DateTime.utc_now(), 30, :second)`, `payload: raw_body`, `signature: the_header_sig`, `created_at: DateTime.utc_now()` via `Repo.insert!/1`, and return `json(conn, %{status: "ok"})` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.3.3.3 Add `post "/gateway/webhooks/:webhook_id", WebhookController, :receive` to `lib/observatory_web/router.ex` in the `:api` pipeline scope; add `get_raw_body` configuration to the endpoint so the raw body bytes are available for HMAC computation `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.3.3.4 Add a `compute_outbound_signature(payload_json, secret)` public function to `Observatory.Gateway.WebhookRouter` that returns `"sha256=#{Base.encode16(:crypto.mac(:hmac, :sha256, secret, payload_json), case: :lower)}"` and is used by `attempt_delivery/1` when constructing the outbound `X-Observatory-Signature` header `done_when: "mix compile --warnings-as-errors"`

### 4.3.4 WebhookRouter Tests

- [ ] **Task 4.3.4 Complete**
- **Governed by:** ADR-020
- **Parent UCs:** UC-0267, UC-0268, UC-0269, UC-0270, UC-0279

Write ExUnit tests for retry schedule, signature validation, startup re-queuing, and thundering-herd cap behaviour.

- [ ] 4.3.4.1 Create `test/observatory/gateway/webhook_router_test.exs` and write tests verifying: (a) `WebhookRouter.compute_outbound_signature/2` returns a string prefixed with `"sha256="`; (b) the retry delay for `attempt_count: 0` is 30 seconds, `attempt_count: 4` is 21600 seconds; (c) after five consecutive delivery failures a `WebhookDelivery` row has `status: "dead"` `done_when: "mix test test/observatory/gateway/webhook_router_test.exs"`
- [ ] 4.3.4.2 Create `test/observatory/gateway/webhook_deliveries_test.exs` and write tests verifying: (a) `WebhookDelivery.changeset/2` is valid with all required fields; (b) a delivery row with `status: "pending"` and `next_retry_at` in the past is found by the polling query; (c) a delivery row with `status: "dead"` is NOT found by the polling query `done_when: "mix test test/observatory/gateway/webhook_deliveries_test.exs"`
- [ ] 4.3.4.3 Create `test/observatory_web/controllers/webhook_controller_test.exs` and write tests verifying: (a) a POST with a valid `X-Observatory-Signature` creates a `webhook_deliveries` row with `status: "pending"` and returns HTTP 200; (b) a POST with a tampered body returns HTTP 401 with `reason: "signature_mismatch"`; (c) a `WebhookSignatureFailureEvent` is broadcast on `"gateway:webhooks"` on signature mismatch `done_when: "mix test test/observatory_web/controllers/webhook_controller_test.exs"`

---

## 4.4 HITLRelay State Machine

- [ ] **Section 4.4 Complete**

This section creates the `Observatory.Gateway.HITLRelay` GenServer that manages the per-session `Normal` / `Paused` state machine, owns the `:hitl_buffer` ETS table, buffers incoming DecisionLog messages while a session is paused, supports in-buffer rewriting by `meta.trace_id`, and flushes the buffer in arrival order on unpause. It also defines the four command types and their required field contracts. By the end of this section, the HITL pause mechanism is fully functional at the GenServer layer, independent of the HTTP and auto-pause layers added in sections 4.5 and 4.6.

### 4.4.1 HITLRelay GenServer and State Machine

- [ ] **Task 4.4.1 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0271, UC-0273

Create `lib/observatory/gateway/hitl_relay.ex` under the module `Observatory.Gateway.HITLRelay`. The GenServer must maintain a state map of the form `%{session_id => :normal | :paused}` and own an ETS table named `:hitl_buffer` with `ordered_set` semantics, created in `init/1`. Expose public functions `pause/4`, `unpause/3`, `rewrite/5`, and `inject/4` that delegate to `GenServer.call/2`.

- [ ] 4.4.1.1 Create `lib/observatory/gateway/hitl_relay.ex` with `use GenServer`, implement `start_link/1` registered as `__MODULE__`, implement `init/1` that creates the ETS table via `:ets.new(:hitl_buffer, [:ordered_set, :public, :named_table])` and returns `{:ok, %{sessions: %{}}}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.4.1.2 Implement `def pause(session_id, agent_id, operator_id, reason)` as `GenServer.call(__MODULE__, {:pause, session_id, agent_id, operator_id, reason})` and the corresponding `handle_call/3` that (a) checks whether `session_id` is already `:paused` in state and returns `{:reply, {:ok, :already_paused}, state}` if so; (b) otherwise transitions the session to `:paused` in state, broadcasts `%HITLGateOpenEvent{session_id: session_id, agent_id: agent_id, operator_id: operator_id, reason: reason, timestamp: DateTime.utc_now()}` on `"session:hitl:#{session_id}"` via `Phoenix.PubSub.broadcast/3`, and returns `{:reply, :ok, updated_state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.4.1.3 Implement `def unpause(session_id, agent_id, operator_id)` as `GenServer.call(__MODULE__, {:unpause, session_id, agent_id, operator_id})` and the corresponding `handle_call/3` that (a) flushes the ETS buffer for key `{session_id, agent_id}` by looking up the ordered list, broadcasting each `%DecisionLog{}` sequentially on the standard DecisionLog PubSub topic via `Phoenix.PubSub.broadcast/3`, deleting the ETS entry via `:ets.delete/2` after the flush, logging any crash at `:error` level with `session_id`; (b) transitions the session to `:normal` in state; (c) broadcasts `%HITLGateCloseEvent{session_id: session_id, agent_id: agent_id, operator_id: operator_id, timestamp: DateTime.utc_now()}` on `"session:hitl:#{session_id}"`; (d) returns `{:reply, :ok, updated_state}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.4.1.4 Add `Observatory.Gateway.HITLRelay` to the application supervisor in `lib/observatory/application.ex` `done_when: "mix compile --warnings-as-errors"`

### 4.4.2 ETS Buffer and Rewrite Support

- [ ] **Task 4.4.2 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0272

Implement the buffer append and in-buffer rewrite functionality. When a session is paused and a DecisionLog arrives for routing, `HITLRelay.buffer_message/3` must append the log to the ETS list for key `{session_id, agent_id}`. The `rewrite/5` function must locate the buffered entry matching `original_trace_id` in `meta.trace_id` and replace its `action.tool_output_summary` (or a nominated content field) with `new_content`; it must return `{:error, :trace_id_not_found_in_buffer}` when no match exists.

- [ ] 4.4.2.1 Implement `def buffer_message(session_id, agent_id, decision_log)` as a `GenServer.cast` that retrieves the current ETS list for `{session_id, agent_id}` via `:ets.lookup(:hitl_buffer, {session_id, agent_id})`, appends `decision_log` to the list, and writes back via `:ets.insert(:hitl_buffer, {{session_id, agent_id}, updated_list})`; the function must be a no-op (forwarding directly via PubSub instead) when the session state is `:normal` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.4.2.2 Implement `def rewrite(session_id, agent_id, original_trace_id, new_content, operator_id)` as `GenServer.call(__MODULE__, {:rewrite, session_id, agent_id, original_trace_id, new_content, operator_id})` and the corresponding `handle_call/3` that looks up the ETS buffer for `{session_id, agent_id}`, searches the list for a `%DecisionLog{}` where `log.meta.trace_id == original_trace_id`, replaces it with `%{log | action: %{log.action | tool_output_summary: new_content}}` in the list, writes the updated list back to ETS, and returns `{:reply, :ok, state}`; if no entry matches `original_trace_id`, returns `{:reply, {:error, :trace_id_not_found_in_buffer}, state}` without modifying the buffer `done_when: "mix compile --warnings-as-errors"`

### 4.4.3 inject Command and Four Command Types

- [ ] **Task 4.4.3 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0274

Implement the `inject/4` public function that constructs a synthetic DecisionLog carrying the operator-supplied prompt and either appends it to the ETS buffer (if the session is paused) or broadcasts it immediately (if the session is normal). Define the `HITLGateOpenEvent` and `HITLGateCloseEvent` structs that are broadcast on the per-session PubSub topic.

- [ ] 4.4.3.1 Define `defstruct`-based structs `Observatory.Gateway.HITLGateOpenEvent` with fields `[:session_id, :agent_id, :operator_id, :reason, :timestamp]` and `Observatory.Gateway.HITLGateCloseEvent` with fields `[:session_id, :agent_id, :operator_id, :timestamp]` in `lib/observatory/gateway/hitl_relay.ex` (or a separate `lib/observatory/gateway/hitl_events.ex` module if line count exceeds 200) `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.4.3.2 Implement `def inject(session_id, agent_id, prompt, operator_id)` as `GenServer.call(__MODULE__, {:inject, session_id, agent_id, prompt, operator_id})` and the corresponding `handle_call/3` that constructs a synthetic `%DecisionLog{}` struct with `meta.trace_id: UUID.uuid4()`, `meta.timestamp: DateTime.utc_now()`, `identity.agent_id: agent_id`, `cognition.intent: "operator_inject"`, `action.status: :success`, `action.tool_call: "hitl_inject"`, `action.tool_output_summary: prompt`; appends the synthetic log to the ETS buffer if the session is `:paused`, or broadcasts it immediately on the standard DecisionLog PubSub topic if the session is `:normal`; returns `{:reply, :ok, state}` `done_when: "mix compile --warnings-as-errors"`

### 4.4.4 HITLRelay State Machine Tests

- [ ] **Task 4.4.4 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0271, UC-0272, UC-0273, UC-0274

Write ExUnit tests covering the state machine transitions, ETS buffer operations, rewrite-then-flush order, and edge cases.

- [ ] 4.4.4.1 Create `test/observatory/gateway/hitl_relay_test.exs` and write tests verifying: (a) `HITLRelay.pause("sess-1", "agent-1", "operator-x", "loop_detected")` returns `:ok` and a `HITLGateOpenEvent` is broadcast on `"session:hitl:sess-1"`; (b) a second `pause` call on an already-paused session returns `{:ok, :already_paused}` without resetting the buffer; (c) `HITLRelay.unpause("sess-1", "agent-1", "operator-x")` returns `:ok` and a `HITLGateCloseEvent` is broadcast `done_when: "mix test test/observatory/gateway/hitl_relay_test.exs"`
- [ ] 4.4.4.2 In `test/observatory/gateway/hitl_relay_test.exs`, write tests verifying: (a) three DecisionLogs buffered during pause are flushed in arrival order on unpause via PubSub; (b) a rewrite targeting a valid `trace_id` modifies the buffered entry so the flushed message has the new content; (c) a rewrite targeting a non-existent `trace_id` returns `{:error, :trace_id_not_found_in_buffer}` and leaves the buffer unchanged; (d) unpause on a session with zero buffered messages does not raise `done_when: "mix test test/observatory/gateway/hitl_relay_test.exs"`

---

## 4.5 HITL HTTP Endpoints & Auth

- [ ] **Section 4.5 Complete**

This section exposes the four HITL HTTP endpoints under `/gateway/sessions/:session_id/`, implements the `Observatory.Plugs.OperatorAuth` plug that enforces the `X-Observatory-Operator-Id` header, creates the `HITLInterventionEvent` Ash resource with its SQLite data layer, and wires the audit trail creation into each successfully processed controller action. By the end of this section, operators can issue HITL commands via HTTP, all requests are authenticated, and every successful command leaves a tamper-evident audit record.

### 4.5.1 OperatorAuth Plug

- [ ] **Task 4.5.1 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0281

Implement `Observatory.Plugs.OperatorAuth` as a Plug that reads the `X-Observatory-Operator-Id` request header, trims whitespace, halts the connection with HTTP 401 if the value is absent or blank, and sets `conn.assigns[:operator_id]` to the trimmed value otherwise. The plug must not validate OAuth tokens in Phase 1; only header presence is checked.

- [ ] 4.5.1.1 Create `lib/observatory/plugs/operator_auth.ex` under module `Observatory.Plugs.OperatorAuth` with `@behaviour Plug`, implement `init/1` that returns opts unchanged, implement `call/2` that reads `conn |> get_req_header("x-observatory-operator-id") |> List.first()`, applies `String.trim/1`, halts with `conn |> put_status(401) |> json(%{status: "error", reason: "missing_operator_id"}) |> halt()` if the trimmed value is empty or nil, otherwise assigns the value to `conn.assigns[:operator_id]` via `assign(conn, :operator_id, trimmed_value)` and returns `conn` `done_when: "mix compile --warnings-as-errors"`

### 4.5.2 HITL Controller and Router Wiring

- [ ] **Task 4.5.2 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0274, UC-0280

Implement `ObservatoryWeb.HITLController` with four actions — `pause/2`, `unpause/2`, `rewrite/2`, and `inject/2` — each of which validates required fields before calling `HITLRelay`, and add all four routes to the Phoenix router under a pipeline that includes `OperatorAuth`.

- [ ] 4.5.2.1 Create `lib/observatory_web/controllers/hitl_controller.ex` under module `ObservatoryWeb.HITLController`; implement `def pause(conn, params)` that validates `params` contains `"agent_id"`, `"operator_id"`, and `"reason"` (all non-empty strings), returns HTTP 422 `{"status": "error", "reason": "missing_required_field: #{field}"}` for the first missing field, and on success calls `HITLRelay.pause(session_id, agent_id, operator_id, reason)` where `session_id` is `conn.path_params["session_id"]` and returns `json(conn, %{status: "ok"})` on `:ok` or `json(conn, %{status: "ok", note: "already_paused"})` on `{:ok, :already_paused}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.5.2.2 In `ObservatoryWeb.HITLController`, implement `def unpause(conn, params)` validating `"agent_id"` and `"operator_id"`, calling `HITLRelay.unpause/3`; implement `def rewrite(conn, params)` validating `"agent_id"`, `"operator_id"`, `"original_trace_id"`, and `"new_content"`, calling `HITLRelay.rewrite/5` and returning HTTP 422 `{"status": "error", "reason": "trace_id_not_found_in_buffer"}` on `{:error, :trace_id_not_found_in_buffer}`; implement `def inject(conn, params)` validating `"agent_id"`, `"operator_id"`, and `"prompt"`, calling `HITLRelay.inject/4`; all success paths return `json(conn, %{status: "ok"})` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.5.2.3 In `lib/observatory_web/router.ex`, define a new pipeline `:hitl_api` that includes `plug :accepts, ["json"]` and `plug Observatory.Plugs.OperatorAuth`; add a scope `"/gateway/sessions/:session_id"` using the `:hitl_api` pipeline with four routes: `post "/pause", HITLController, :pause`, `post "/unpause", HITLController, :unpause`, `post "/rewrite", HITLController, :rewrite`, `post "/inject", HITLController, :inject` `done_when: "mix compile --warnings-as-errors"`

### 4.5.3 HITLInterventionEvent Ash Resource

- [ ] **Task 4.5.3 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0275

Create the `Observatory.Gateway.HITLInterventionEvent` Ash resource at `lib/observatory/gateway/hitl_intervention_event.ex` using the SQLite data layer. The resource must define all required attributes including the `command_type` atom enum, `before_state` and `after_state` SHA-256 hash fields, and the nullable `reversed_at` field. A `:create` action must accept all fields. Wire creation into the HITLController actions.

- [ ] 4.5.3.1 Create `lib/observatory/gateway/hitl_intervention_event.ex` under module `Observatory.Gateway.HITLInterventionEvent` using `use Ash.Resource, data_layer: AshSqlite.DataLayer`, define attributes: `uuid_primary_key :id`, `attribute :session_id, :string, allow_nil?: false`, `attribute :agent_id, :string, allow_nil?: false`, `attribute :operator_id, :string, allow_nil?: false`, `attribute :command_type, :atom, constraints: [one_of: [:hitl_pause, :hitl_rewrite, :hitl_inject, :hitl_unpause]], allow_nil?: false`, `attribute :before_state, :string`, `attribute :after_state, :string`, `attribute :timestamp, :utc_datetime, allow_nil?: false`, `attribute :reversed_at, :utc_datetime`; define a `:create` action that accepts all attributes `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.5.3.2 Generate and run the Ash migration for `HITLInterventionEvent` via `mix ash.codegen hitl_intervention_event && mix ash.migrate`, confirm the `hitl_intervention_events` table is created with all columns `done_when: "mix ash.migrate && mix compile --warnings-as-errors"`
- [ ] 4.5.3.3 Add a private `create_audit_event/4` helper in `ObservatoryWeb.HITLController` that calls `Ash.create!(HITLInterventionEvent, %{session_id: session_id, agent_id: agent_id, operator_id: operator_id, command_type: command_type, before_state: before_hash, after_state: after_hash, timestamp: DateTime.utc_now()})` where `before_hash` and `after_hash` are `:crypto.hash(:sha256, inspect(log)) |> Base.encode16(case: :lower)` for targeted commands and `nil` for non-targeted commands (pause/unpause); call `create_audit_event/4` at the end of each controller action success path `done_when: "mix compile --warnings-as-errors"`

### 4.5.4 HITL Controller Tests

- [ ] **Task 4.5.4 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0274, UC-0275, UC-0280, UC-0281

Write ExUnit tests for the controller actions, authentication plug, audit trail creation, and error paths.

- [ ] 4.5.4.1 Create `test/observatory_web/controllers/hitl_controller_test.exs` and write tests verifying: (a) `POST /gateway/sessions/sess-1/pause` with valid body and `X-Observatory-Operator-Id: operator-x` returns HTTP 200 `{"status": "ok"}`; (b) missing `X-Observatory-Operator-Id` header returns HTTP 401 with `reason: "missing_operator_id"` and HITLRelay is never called; (c) `X-Observatory-Operator-Id: ` (whitespace only) is treated as missing and returns HTTP 401 `done_when: "mix test test/observatory_web/controllers/hitl_controller_test.exs"`
- [ ] 4.5.4.2 In `test/observatory_web/controllers/hitl_controller_test.exs`, write tests verifying: (a) a `POST /rewrite` missing `original_trace_id` returns HTTP 422 with `reason: "missing_required_field: original_trace_id"`; (b) a `POST /rewrite` with a non-existent `original_trace_id` returns HTTP 422 with `reason: "trace_id_not_found_in_buffer"`; (c) a successful `POST /pause` creates a `HITLInterventionEvent` row with `command_type: :hitl_pause`, `before_state: nil`, and `after_state: nil`; (d) a successful `POST /rewrite` creates a `HITLInterventionEvent` row with non-nil `before_state` and `after_state` SHA-256 hex strings `done_when: "mix test test/observatory_web/controllers/hitl_controller_test.exs"`

---

## 4.6 Auto-Pause & Operator Actions

- [ ] **Section 4.6 Complete**

This section wires the `SchemaInterceptor` to auto-pause sessions when `control.hitl_required == true` is detected on an incoming DecisionLog, implements the three operator approval actions (Approve, Rewrite, Reject) at the LiveView layer in the Session Drill-down, and defines the diamond DAG node rendering for `HITLInterventionEvent` records in the causal DAG timeline. By the end of this section, the full HITL flow — from agent-flagged message to operator approval and resumption — is functional end to end.

### 4.6.1 SchemaInterceptor Auto-Pause Extension

- [ ] **Task 4.6.1 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0276

Extend the Phase 2 `SchemaInterceptor` module to detect `control.hitl_required == true` on every validated DecisionLog and call `HITLRelay.pause/4` before any downstream broadcast. The triggering DecisionLog must be placed as the first entry in the ETS buffer rather than forwarded, so downstream consumers (Topology Engine, Entropy Alerter) cannot act on an unapproved message.

- [ ] 4.6.1.1 In `lib/observatory/gateway/schema_interceptor.ex`, add a private function `maybe_auto_pause/1` that receives a `%DecisionLog{}` struct and checks `log.control && log.control.hitl_required == true`; when true, calls `HITLRelay.pause(log.meta.cluster_id, log.identity.agent_id, "system", "hitl_required_flag")`, then calls `HITLRelay.buffer_message(session_id, log.identity.agent_id, log)` to place the triggering DecisionLog into the buffer, and returns `{:paused, log}`; when false or nil, returns `{:normal, log}` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.6.1.2 In the SchemaInterceptor's post-validation dispatch pipeline, call `maybe_auto_pause(decision_log)` first; on `{:paused, _log}`, skip the downstream PubSub broadcast for the DecisionLog (it is in the buffer); on `{:normal, log}`, proceed with the existing broadcast path including the `maybe_schedule_reminder/1` call from section 4.2.3 `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.6.1.3 Write a test in `test/observatory/gateway/schema_interceptor_test.exs` (or create this file if absent) verifying that a validated DecisionLog with `control.hitl_required: true` triggers a `HITLGateOpenEvent` broadcast on `"session:hitl:#{session_id}"` and is NOT broadcast on the standard DecisionLog PubSub topic until `HITLRelay.unpause/3` is called `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs"`

### 4.6.2 Session Drill-down Approval Gate UI

- [ ] **Task 4.6.2 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0277, UC-0282

Implement the approval gate UI in the Session Drill-down LiveView. The LiveView must subscribe to `"session:hitl:#{session_id}"` in `mount/3`, display the approval gate with buffered message content when a `HITLGateOpenEvent` is received, and offer three operator actions (Approve, Rewrite, Reject) that each issue the correct sequence of HTTP calls to the HITL endpoints.

- [ ] 4.6.2.1 Create `lib/observatory_web/live/session_drilldown_live.ex` under module `ObservatoryWeb.SessionDrilldownLive` (or locate the existing session detail LiveView in the project); add `Phoenix.PubSub.subscribe(Observatory.PubSub, "session:hitl:#{session_id}")` in `mount/3`; implement `handle_info(%HITLGateOpenEvent{} = event, socket)` that sets `socket.assigns[:hitl_gate_open] = true` and `socket.assigns[:hitl_event] = event`; implement `handle_info(%HITLGateCloseEvent{}, socket)` that clears `hitl_gate_open` `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.6.2.2 In the Session Drill-down template, conditionally render an approval gate panel when `@hitl_gate_open` is true, displaying: (a) the buffered message summary; (b) an Approve button that calls `POST /gateway/sessions/#{session_id}/unpause`; (c) a Rewrite form with a textarea pre-populated with the buffered message content and a Submit button that calls `POST /gateway/sessions/#{session_id}/rewrite` with the edited content followed immediately by `POST /gateway/sessions/#{session_id}/unpause`; (d) a Reject button that calls `POST /gateway/sessions/#{session_id}/inject` with `prompt: "action rejected by operator, do not retry"` followed by `POST /gateway/sessions/#{session_id}/unpause` `done_when: "mix compile --warnings-as-errors"`

### 4.6.3 Diamond DAG Node for HITL Interventions

- [ ] **Task 4.6.3 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0278

Implement the diamond-shaped DAG node rendering for `HITLInterventionEvent` records in the causal DAG timeline component. The diamond node must be inserted at the correct temporal position (derived from `HITLInterventionEvent.timestamp`), grouped by pause window, and display a count badge when multiple interventions share the same pause window.

- [ ] 4.6.3.1 In the causal DAG rendering component (located in the Session Drill-down or a shared DAG component), add a query for `HITLInterventionEvent` rows by `session_id` ordered by `timestamp`, and merge the intervention events into the DAG node list by inserting a sentinel `{:hitl_intervention, events}` entry between the last DecisionLog before the pause timestamp and the first DecisionLog after the unpause timestamp `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.6.3.2 Implement a `hitl_diamond_node/1` function component in the appropriate components module that renders a diamond-shaped SVG or CSS element; accepts a list of `HITLInterventionEvent` structs; displays a count badge showing `length(events)` when more than one event is present; renders a tooltip (via `title` attribute or Tippy.js) showing `operator_id`, `command_type`, and `timestamp` from the first event in the group `done_when: "mix compile --warnings-as-errors"`
- [ ] 4.6.3.3 Write a test in `test/observatory_web/live/session_drilldown_live_test.exs` verifying: (a) the LiveView subscribes to `"session:hitl:#{session_id}"` at mount; (b) receiving a `HITLGateOpenEvent` causes `assigns.hitl_gate_open` to be truthy; (c) receiving a `HITLGateCloseEvent` causes `assigns.hitl_gate_open` to be falsy `done_when: "mix test test/observatory_web/live/session_drilldown_live_test.exs"`

### 4.6.4 End-to-End HITL Integration Tests

- [ ] **Task 4.6.4 Complete**
- **Governed by:** ADR-021
- **Parent UCs:** UC-0271, UC-0272, UC-0273, UC-0276, UC-0277

Write integration-level tests that exercise the full auto-pause flow from SchemaInterceptor detection through HITLRelay state machine through HTTP endpoint approval to buffer flush.

- [ ] 4.6.4.1 In `test/observatory/gateway/hitl_relay_test.exs`, write an integration test that: submits a DecisionLog with `control.hitl_required: true` to the SchemaInterceptor's process pipeline; asserts the standard DecisionLog PubSub topic does NOT receive the message; sends a `POST /gateway/sessions/:session_id/unpause` via the test HTTP client with a valid operator header; asserts the standard DecisionLog PubSub topic DOES receive the buffered message after the unpause `done_when: "mix test test/observatory/gateway/hitl_relay_test.exs"`
- [ ] 4.6.4.2 In `test/observatory/gateway/hitl_relay_test.exs`, write an integration test for the Reject path: pause a session via `HITLRelay.pause/4`; call `POST /gateway/sessions/:session_id/inject` with `prompt: "action rejected by operator, do not retry"` then `POST /gateway/sessions/:session_id/unpause`; assert the PubSub topic receives the synthetic injection message first, then any other buffered messages in order `done_when: "mix test test/observatory/gateway/hitl_relay_test.exs"`

---
