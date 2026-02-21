---
id: FRD-011
title: HITL Intervention API Functional Requirements
date: 2026-02-22
status: draft
source_adr: [ADR-021]
related_rule: []
---

# FRD-011: HITL Intervention API

## Purpose

The Human-in-the-Loop (HITL) Intervention API gives operators the ability to pause an agent session mid-flight, inspect or rewrite its buffered messages, inject new prompts, and then unpause the session to resume normal operation. This capability is essential when an agent's DecisionLog signals that human approval is required before an action may proceed — either because the `control.hitl_required` flag is set in the incoming message, or because an operator intervenes proactively via the HTTP API.

The subsystem is implemented as `Observatory.Gateway.HITLRelay`, a GenServer that owns the pause state machine for every active session. All interventions are persisted to an Ash resource audit trail and broadcast over a per-session PubSub topic so that the LiveView Session Drill-down can render the intervention as a diamond-shaped node in the causal DAG at the exact point the pause occurred.

## Functional Requirements

### FR-11.1: HITLRelay Module Location and State Machine

The HITL relay MUST be implemented at `lib/observatory/gateway/hitl_relay.ex` under the module `Observatory.Gateway.HITLRelay`. The module MUST implement a two-state machine per session: `Normal` and `Paused`. The valid transitions are `Normal → Paused` (triggered by the `hitl_pause` command or automatic detection of `control.hitl_required == true`) and `Paused → Normal` (triggered by the `hitl_unpause` command). A session in `Normal` state MUST NOT buffer incoming DecisionLog messages; they MUST be forwarded immediately on their standard PubSub topic. A session in `Paused` state MUST buffer all incoming DecisionLog messages and MUST NOT forward them until the session is unpaused. No other state transitions are defined in Phase 1.

**Positive path**: Session "sess-abc" is in `Normal` state. An operator sends `POST /gateway/sessions/sess-abc/pause`. HITLRelay transitions "sess-abc" to `Paused`. Subsequent DecisionLog messages from "sess-abc" are buffered rather than forwarded. The operator later sends `POST /gateway/sessions/sess-abc/unpause`. HITLRelay transitions back to `Normal` and flushes the buffer in order.

**Negative path**: A second `hitl_pause` command arrives for a session already in `Paused` state. HITLRelay MUST treat this as a no-op and return HTTP 200 `{"status": "ok", "note": "already_paused"}` rather than resetting the buffer or raising an error.

---

### FR-11.2: ETS Buffer Keyed by {session_id, agent_id}

While a session is in `Paused` state, every incoming DecisionLog message addressed to that session MUST be stored in an ETS table owned by the HITLRelay GenServer. The ETS key MUST be the tuple `{session_id, agent_id}`. Each key MUST map to an ordered list of buffered DecisionLog structs, appended in arrival order. The ETS table MUST be named `:hitl_buffer` and MUST use `ordered_set` semantics to preserve insertion ordering by key. When a Rewrite command is received before unpause, the HITLRelay MUST locate the buffered entry whose `meta.trace_id` matches `original_trace_id` and replace its content with `new_content` in the buffer before the flush occurs. Buffered entries MUST NOT be forwarded until `hitl_unpause` is processed.

**Positive path**: Session "sess-abc" is paused. Agent "agent-1" sends three DecisionLog messages with trace_ids T1, T2, T3. ETS key `{"sess-abc", "agent-1"}` maps to `[log_T1, log_T2, log_T3]`. Before unpause, an operator issues `hitl_rewrite` targeting `original_trace_id: "T2"` with `new_content: "revised reasoning"`. The buffer becomes `[log_T1, log_T2_rewritten, log_T3]`. Unpause forwards all three in that order.

**Negative path**: If `original_trace_id` in a `hitl_rewrite` command does not match any buffered entry for `{session_id, agent_id}`, the HITLRelay MUST return HTTP 422 `{"status": "error", "reason": "trace_id_not_found_in_buffer"}` and MUST NOT modify any buffered entries.

---

### FR-11.3: Unpause Flush Order with Rewrite Applied

When `hitl_unpause` is processed, HITLRelay MUST forward all buffered DecisionLog messages for `{session_id, agent_id}` in their original arrival order, with any Rewrite modifications applied in place. The flush MUST be a sequential PubSub broadcast: each message MUST be broadcast and acknowledged before the next is sent, using `Phoenix.PubSub.broadcast/3` on the standard DecisionLog topic for that session. After the flush completes, the ETS buffer entry for `{session_id, agent_id}` MUST be deleted. If no messages were buffered (the session was paused but no DecisionLogs arrived), the unpause MUST still transition the state machine to `Normal` and MUST NOT raise on an empty buffer flush.

**Positive path**: "sess-abc" unpauses with three buffered messages `[log_T1, log_T2_rewritten, log_T3]`. HITLRelay broadcasts `log_T1`, then `log_T2_rewritten`, then `log_T3` in that order on the session's DecisionLog PubSub topic. After all three are broadcast, the ETS entry is deleted. The session transitions to `Normal`.

**Negative path**: If the GenServer crashes mid-flush (after broadcasting log_T1 but before log_T2), the remaining buffer is lost because ETS tables are owned by the crashed process. Phase 1 does not provide crash-safe flush durability. The FRD acknowledges this limitation and defers durable flush to Phase 2. The crash MUST be logged at `:error` level with the session_id so operators can detect partial flushes.

---

### FR-11.4: Four Command Types and Required Fields

HITLRelay MUST support exactly four command types, each delivered either via HTTP or via the CommandQueue file format at `~/.claude/inbox/{session_id}/{id}.json`. The required fields for each command type are as follows. `hitl_pause`: `type`, `session_id`, `agent_id`, `operator_id`, `reason` (string), `timestamp` (ISO 8601 UTC). `hitl_rewrite`: `type`, `session_id`, `agent_id`, `original_trace_id` (UUID string matching a buffered DecisionLog's `meta.trace_id`), `new_content` (string), `operator_id`, `timestamp`. `hitl_inject`: `type`, `session_id`, `agent_id`, `prompt` (string to inject as a synthetic message), `operator_id`, `timestamp`. `hitl_unpause`: `type`, `session_id`, `agent_id`, `operator_id`, `timestamp`. A command missing any required field MUST be rejected with HTTP 422. A command whose `type` is not one of these four values MUST be rejected with HTTP 422.

**Positive path**: A `hitl_inject` command body contains all five required fields. HITLRelay accepts it, constructs a synthetic DecisionLog carrying the `prompt` content, and — if the session is in `Paused` state — appends it to the ETS buffer. If the session is in `Normal` state, the inject MUST broadcast the synthetic message immediately without buffering.

**Negative path**: A `hitl_rewrite` command body omits `original_trace_id`. The controller validates required fields before calling HITLRelay and returns HTTP 422 `{"status": "error", "reason": "missing_required_field: original_trace_id"}`. HITLRelay is never called.

---

### FR-11.5: Four HTTP Endpoints

HITLRelay MUST be reachable via four HTTP endpoints, all scoped under `/gateway/sessions/:session_id/`: `POST /gateway/sessions/:session_id/pause` invokes the `hitl_pause` command; `POST /gateway/sessions/:session_id/unpause` invokes the `hitl_unpause` command; `POST /gateway/sessions/:session_id/rewrite` invokes the `hitl_rewrite` command; `POST /gateway/sessions/:session_id/inject` invokes the `hitl_inject` command. All four endpoints MUST be defined in the Phoenix router under a pipeline that includes the operator authentication plug described in FR-11.6. All four MUST return HTTP 200 `{"status": "ok"}` on success. The `:session_id` path parameter MUST be passed through to the command payload as `session_id`.

**Positive path**: `POST /gateway/sessions/sess-abc/pause` with a valid JSON body and a valid `X-Observatory-Operator-Id` header returns HTTP 200. HITLRelay transitions "sess-abc" to `Paused`. The LiveView subscribed to `"session:hitl:sess-abc"` receives a `HITLGateOpenEvent`.

**Negative path**: A request to `POST /gateway/sessions/sess-abc/pause` missing the `X-Observatory-Operator-Id` header is rejected by the authentication plug before reaching the controller. The response MUST be HTTP 401 `{"status": "error", "reason": "missing_operator_id"}`. HITLRelay MUST NOT be called.

---

### FR-11.6: Operator Authentication via X-Observatory-Operator-Id Header

All four HITL HTTP endpoints MUST require the request header `X-Observatory-Operator-Id` containing a non-empty string identifying the operator performing the intervention. In Phase 1, the plug MUST validate only that the header is present and non-empty; it MUST store the value as `conn.assigns[:operator_id]` for downstream use in audit logging. The plug MUST NOT perform OAuth token validation in Phase 1. A missing or empty header MUST result in HTTP 401 before the request body is parsed. Phase 2 OAuth integration MUST NOT require changes to the controller or HITLRelay module; only the plug implementation changes.

**Positive path**: A request arrives with header `X-Observatory-Operator-Id: operator-xander`. The plug finds the header, sets `conn.assigns[:operator_id] = "operator-xander"`, and calls `next` in the plug pipeline. The controller reads `conn.assigns[:operator_id]` and includes it in the `HITLInterventionEvent` audit record.

**Negative path**: A request arrives with header `X-Observatory-Operator-Id: ` (whitespace only). The plug MUST treat a blank or whitespace-only value as absent and return HTTP 401. `String.trim/1` MUST be applied before the presence check.

---

### FR-11.7: HITLInterventionEvent Audit Trail

Every successfully processed HITL command MUST create a row in the `HITLInterventionEvent` Ash resource. The resource MUST have the following fields: `id` (UUID, primary key), `session_id` (string, not null), `agent_id` (string, not null), `operator_id` (string, not null), `command_type` (atom enum: `:hitl_pause`, `:hitl_rewrite`, `:hitl_inject`, `:hitl_unpause`, not null), `before_state` (string — SHA-256 hash of the affected DecisionLog struct, nullable for commands that do not target a specific message), `after_state` (string — SHA-256 hash of the resulting DecisionLog struct after any modification, nullable), `timestamp` (`:utc_datetime`, not null), and `reversed_at` (`:utc_datetime`, nullable — set when a subsequent `hitl_rewrite` or `hitl_unpause` supersedes this intervention). The Ash resource MUST use the SQLite data layer and MUST be defined in `lib/observatory/gateway/hitl_intervention_event.ex`.

**Positive path**: An operator issues `hitl_rewrite` targeting `trace_id: "T2"`. HITLRelay modifies the buffered log. After the modification, the controller creates a `HITLInterventionEvent` row with `command_type: :hitl_rewrite`, `before_state: sha256(log_T2_original)`, `after_state: sha256(log_T2_rewritten)`, `operator_id: "operator-xander"`, and `reversed_at: nil`.

**Negative path**: A `hitl_pause` command does not target a specific DecisionLog. The `HITLInterventionEvent` row MUST be created with `before_state: nil` and `after_state: nil` rather than crashing on a nil hash computation. The `command_type: :hitl_pause` record is still written for audit completeness.

---

### FR-11.8: session:hitl:{session_id} PubSub Topic

HITLRelay MUST broadcast state change events on the PubSub topic `"session:hitl:#{session_id}"` using `Phoenix.PubSub.broadcast(Observatory.PubSub, "session:hitl:#{session_id}", event)`. When a session transitions from `Normal` to `Paused`, HITLRelay MUST broadcast a `%HITLGateOpenEvent{session_id: session_id, agent_id: agent_id, operator_id: operator_id, reason: reason, timestamp: timestamp}` struct. When a session transitions from `Paused` to `Normal`, HITLRelay MUST broadcast a `%HITLGateCloseEvent{session_id: session_id, agent_id: agent_id, operator_id: operator_id, timestamp: timestamp}` struct. The Session Drill-down LiveView MUST subscribe to this topic on mount and MUST update its UI state in response to these events.

**Positive path**: A LiveView rendering session "sess-abc" calls `Phoenix.PubSub.subscribe(Observatory.PubSub, "session:hitl:sess-abc")` in `mount/3`. When an operator pauses the session, the LiveView receives `%HITLGateOpenEvent{...}` and renders the approval gate UI. When the operator unpauses, the LiveView receives `%HITLGateCloseEvent{...}` and hides the approval gate.

**Negative path**: If the LiveView subscribes to `"session:hitl"` (without the session_id suffix), it receives events for all sessions and cannot isolate the relevant session. The subscription MUST always include the full topic string `"session:hitl:#{session_id}"` with the specific session scoped at mount time.

---

### FR-11.9: Automatic Pause on control.hitl_required == true

The SchemaInterceptor MUST inspect every validated DecisionLog for `control.hitl_required == true`. When this flag is true, the SchemaInterceptor MUST call `HITLRelay.pause(session_id, agent_id, operator_id: "system", reason: "hitl_required_flag")` before forwarding the DecisionLog on any PubSub topic. The triggering DecisionLog MUST be the first entry placed in the ETS buffer, not forwarded ahead of the pause. A `HITLGateOpenEvent` MUST be broadcast on `"session:hitl:#{session_id}"`. The UI MUST display the approval gate with the buffered message content visible to the operator. If `control.hitl_required` is nil or false, the SchemaInterceptor MUST skip this step and forward the DecisionLog normally.

**Positive path**: An agent submits a DecisionLog with `control.hitl_required: true`. The SchemaInterceptor detects the flag, calls `HITLRelay.pause("sess-abc", "agent-1", ...)`, places the DecisionLog in the ETS buffer, and broadcasts `HITLGateOpenEvent`. The Session Drill-down shows the approval gate with the buffered log's content. The DecisionLog is not broadcast on the standard topic until the operator acts.

**Negative path**: If the SchemaInterceptor forwards the DecisionLog on PubSub before calling `HITLRelay.pause`, downstream consumers (Topology Engine, Entropy Alerter) process the message before the operator has a chance to approve or rewrite it. The pause call and buffer insertion MUST happen before any downstream broadcast.

---

### FR-11.10: Operator Approval, Rewrite, and Reject Actions

The Session Drill-down LiveView MUST present an approval gate UI whenever a `HITLGateOpenEvent` is received. The gate MUST offer three operator actions. Approve: the operator clicks Approve; the LiveView calls `POST /gateway/sessions/:session_id/unpause`; HITLRelay flushes the buffer as-is and transitions to `Normal`. Rewrite: the operator edits the buffered message content in the UI and submits; the LiveView calls `POST /gateway/sessions/:session_id/rewrite` with the edited content as `new_content` targeting the buffered message's `meta.trace_id`, then immediately calls `POST /gateway/sessions/:session_id/unpause`; HITLRelay applies the rewrite and flushes. Reject: the operator clicks Reject; the LiveView calls `POST /gateway/sessions/:session_id/inject` with `prompt: "action rejected by operator, do not retry"` then immediately calls `POST /gateway/sessions/:session_id/unpause`; HITLRelay injects the rejection prompt and flushes in order (inject prompt first, then any other buffered messages).

**Positive path**: An operator receives a gate with a pending `schedule_deletion` action. The operator clicks Reject. The LiveView POSTs to `/inject` with the rejection prompt, then POSTs to `/unpause`. The agent receives `"action rejected by operator, do not retry"` as a synthetic message followed by its subsequent buffered DecisionLogs. The agent's next DecisionLog reflects acknowledgment of the rejection.

**Negative path**: If the Reject action only calls `/unpause` without calling `/inject` first, the agent receives no feedback about the rejection and may retry the action autonomously. The Reject path MUST always inject the rejection prompt before unpausing.

---

### FR-11.11: Diamond DAG Node for HITL Interventions

The Session Drill-down causal DAG MUST render every `HITLInterventionEvent` associated with a session as a diamond-shaped node at the position in the timeline where the pause occurred. The node MUST be inserted between the last forwarded DecisionLog node (before the pause) and the first forwarded DecisionLog node (after the unpause). The node MUST display `operator_id`, `command_type`, and `timestamp` as tooltip or inline label content. Diamond nodes MUST be visually distinct from standard rectangular DecisionLog nodes and terminal circular nodes. If multiple interventions occurred at the same pause point (e.g., a `hitl_pause` followed by a `hitl_rewrite` before `hitl_unpause`), all intervention events for that pause window MUST be grouped into a single diamond node with a count badge indicating how many commands were issued.

**Positive path**: A session has three forwarded DecisionLogs (T1, T2, T3), then a pause with one `hitl_rewrite` intervention, then one forwarded DecisionLog (T3_rewritten). The DAG renders: rect(T1) → rect(T2) → diamond(1 intervention) → rect(T3_rewritten). The diamond tooltip shows `operator_id: "operator-xander"`, `command_type: :hitl_rewrite`, and the intervention timestamp.

**Negative path**: If the diamond node is placed after T3_rewritten rather than between T2 and T3_rewritten, the visual timeline misrepresents when the intervention occurred. The node's DAG position MUST be derived from the `HITLInterventionEvent.timestamp` field, not from the timestamp of the first post-unpause DecisionLog.

---

## Out of Scope (Phase 1)

- OAuth 2.0 token validation for the X-Observatory-Operator-Id header
- Crash-safe durable flush across GenServer restarts during mid-buffer unpause
- Multi-operator concurrent pause arbitration (last-write-wins in Phase 1)
- HITL buffer persistence to SQLite (ETS only in Phase 1)
- Automated approval policies (rule-based auto-approve without operator input)
- HITL intervention for non-DecisionLog message types

## Related ADRs

- [ADR-021](../../decisions/ADR-021-hitl-intervention-api.md) -- Defines HITLRelay module, pause state machine, ETS buffer keying, command types, HTTP endpoints, operator authentication, audit trail fields, PubSub topic, automatic pause on hitl_required, operator approval actions, and DAG diamond node rendering
