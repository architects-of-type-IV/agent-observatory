---
id: FRD-007
title: Gateway Schema Interceptor Functional Requirements
date: 2026-02-22
status: draft
source_adr: [ADR-013, ADR-015]
related_rule: []
---

# FRD-007: Gateway Schema Interceptor

## Purpose

The Gateway Schema Interceptor is the first layer of the Hypervisor processing pipeline. Every message from an external agent enters the Observatory through a single HTTP endpoint and is synchronously validated against the DecisionLog schema before any downstream processing occurs. Messages that fail validation are rejected immediately with a structured error response, and a `SchemaViolationEvent` is broadcast so the UI can surface the violation in real time.

The interceptor enforces a strict module boundary: all Gateway code lives in `lib/observatory/gateway/` and communicates with the rest of the system exclusively through Phoenix PubSub topics. This boundary prevents UI-layer concerns from leaking into the Gateway and prevents the Gateway from coupling to any LiveView module.

## Functional Requirements

### FR-7.1: Module Boundary Enforcement

`Observatory.Gateway.SchemaInterceptor` MUST be defined in `lib/observatory/gateway/schema_interceptor.ex`. All modules under the `Observatory.Gateway.*` namespace MUST NOT import, alias, or call any module under the `ObservatoryWeb.*` namespace. All modules under the `ObservatoryWeb.*` namespace MUST NOT call any module under the `Observatory.Gateway.*` namespace directly; they MUST communicate exclusively via Phoenix PubSub topics. This constraint MUST be documented in a module-level `@moduledoc` note in `SchemaInterceptor` and MAY be enforced by a Credo custom check in a later phase. A `mix compile --warnings-as-errors` build MUST pass with zero warnings, but the boundary violation is a design constraint enforced by code review in Phase 1.

**Positive path**: A LiveView component that needs to display schema violations subscribes to `"gateway:violations"` via `Phoenix.PubSub.subscribe/2` and receives broadcast structs. It never calls `SchemaInterceptor.validate/1` directly.

**Negative path**: A developer adds `alias Observatory.Gateway.SchemaInterceptor` in a LiveView module. Code review MUST catch this as a boundary violation. The build does not automatically fail in Phase 1, but the violation is treated as a blocking review comment.

---

### FR-7.2: validate/1 Synchronous Contract

`Observatory.Gateway.SchemaInterceptor` MUST expose a public function `validate/1` that accepts a raw params map (string-keyed) decoded from the HTTP request body and returns either `{:ok, %Observatory.Mesh.DecisionLog{}}` or `{:error, %Ecto.Changeset{}}`. The function MUST be synchronous: it MUST complete before the HTTP controller returns a response. It MUST NOT spawn a Task, GenServer call, or any asynchronous process to perform validation. The function MUST delegate to `Observatory.Mesh.DecisionLog.changeset/2` internally and check `Ecto.Changeset.valid?/1` to determine the return branch.

**Positive path**: A controller calls `SchemaInterceptor.validate(params)` and receives `{:ok, log}` within the same process. The controller immediately forwards `log` to the PubSub router without awaiting any async result.

**Negative path**: A payload missing `meta.timestamp` causes `validate/1` to return `{:error, changeset}` where `changeset.errors` contains `[timestamp: {"can't be blank", [validation: :required]}]`. The controller pattern-matches on `{:error, changeset}` and proceeds to build the rejection response.

---

### FR-7.3: HTTP Endpoint POST /gateway/messages

The Observatory router MUST define a POST route at `/gateway/messages` handled by a controller action in `ObservatoryWeb.GatewayController`. The route MUST be placed in a pipeline that includes JSON body parsing via `Plug.Parsers` with the `:json` parser and the `Jason` library. The route MUST NOT require user session authentication (agents do not hold browser sessions), but it MAY require a bearer token or API key in a later phase. In Phase 1, the endpoint MUST be accessible without authentication. The controller MUST call `SchemaInterceptor.validate/1` as its first action after decoding the body.

**Positive path**: An agent sends `POST /gateway/messages` with a valid JSON body and receives HTTP 200 (or 202) with `{"status": "accepted", "trace_id": "<uuid>"}` in the response body.

**Negative path**: An agent sends a request to `/gateway/message` (singular, typo) and receives HTTP 404 from the Phoenix router. The SchemaInterceptor is never invoked.

---

### FR-7.4: HTTP 422 Response on Schema Violation

When `SchemaInterceptor.validate/1` returns `{:error, changeset}`, the controller MUST respond with HTTP status 422 and a JSON body conforming to: `{"status": "rejected", "reason": "schema_violation", "detail": "<human-readable description of the first validation error>", "trace_id": null}`. The `detail` field MUST be derived from the changeset errors using `Ecto.Changeset.traverse_errors/2` or equivalent. The `trace_id` field MUST be `null` because the message was rejected before a valid `meta.trace_id` was confirmed. The response MUST set `Content-Type: application/json`.

**Positive path**: A payload missing `identity.agent_id` causes the controller to respond with HTTP 422 and body `{"status": "rejected", "reason": "schema_violation", "detail": "agent_id: can't be blank", "trace_id": null}`.

**Negative path**: The controller MUST NOT respond with HTTP 400 for schema validation failures. HTTP 400 is reserved for malformed JSON that cannot be decoded by `Plug.Parsers`. A well-formed JSON body that fails schema validation MUST produce 422, not 400, so callers can distinguish parse errors from semantic errors.

---

### FR-7.5: SchemaViolationEvent Construction

After a validation failure, the Gateway MUST construct a `SchemaViolationEvent` map with exactly the following fields before broadcasting: `event_type` set to the string `"schema_violation"`, `timestamp` set to the current UTC datetime in ISO 8601 format, `agent_id` extracted from `params["identity"]["agent_id"]` (or `"unknown"` if absent), `capability_version` extracted from `params["identity"]["capability_version"]` (or `"unknown"` if absent), `violation_reason` set to a string describing the first validation error (e.g., `"missing required field: meta.trace_id"`), and `raw_payload_hash` set to a SHA-256 hex digest of the raw request body string prefixed with `"sha256:"`. The event MUST be a plain Elixir map, not an Ecto struct, because it is broadcast directly over PubSub and consumed by UI subscribers that pattern-match on map keys.

**Positive path**: A rejection event carries `%{"event_type" => "schema_violation", "agent_id" => "agent-42", "capability_version" => "1.0.0", "violation_reason" => "missing required field: meta.trace_id", "raw_payload_hash" => "sha256:a3f9..."}`.

**Negative path**: If the raw request body is unavailable at the point of event construction (e.g., already consumed by `Plug.Parsers` into a params map), the Gateway MUST hash the JSON-encoded params map as a fallback and MUST NOT omit `raw_payload_hash` from the event. The hash MUST always be present.

---

### FR-7.6: raw_payload_hash Security Policy

The `SchemaViolationEvent` MUST include a hash of the rejected payload for forensic correlation, but MUST NOT include the raw payload content itself. The raw payload MUST NOT be stored in ETS, written to disk, logged at any level, or included in any PubSub broadcast. The hash value MUST be computed using `:crypto.hash(:sha256, raw_body)` and hex-encoded with `Base.encode16/2` in lowercase, then prefixed with `"sha256:"` to produce the final string. This policy prevents untrusted agent-supplied content from entering Observatory's storage or log streams while still enabling operators to correlate a violation event with an external audit log entry that contains the full payload.

**Positive path**: The violation event carries `"raw_payload_hash": "sha256:4d7a8c..."`. An operator with access to the external audit log can locate the matching entry by comparing hashes. The raw payload never appears in Observatory logs or ETS.

**Negative path**: A developer adds `Logger.debug("rejected payload: #{inspect(params)}")` to the rejection branch. This MUST be caught in code review as a violation of the security policy. The policy MUST be documented in the `@moduledoc` of `SchemaInterceptor` so the constraint is visible to all contributors.

---

### FR-7.7: PubSub Broadcast to "gateway:violations"

After constructing the `SchemaViolationEvent`, the Gateway MUST broadcast it on the PubSub topic `"gateway:violations"` using `Phoenix.PubSub.broadcast/3` with the Observatory application's PubSub instance (typically `Observatory.PubSub`). The broadcast MUST occur after the HTTP 422 response has been sent (or in parallel via `Task.start/1` so that response latency is not increased). The event key in the broadcast MUST be `:schema_violation` so that LiveView subscribers can pattern-match on `%{schema_violation: event}` in their `handle_info/2` callbacks.

**Positive path**: A Fleet Command LiveView subscriber receives `{:schema_violation, %{"agent_id" => "agent-42", ...}}` in its `handle_info/2` and renders a flash message `"Agent agent-42 (1.0.0) sent malformed message"`.

**Negative path**: If `Phoenix.PubSub.broadcast/3` returns `{:error, reason}`, the Gateway MUST log a warning-level message `"Failed to broadcast schema_violation event: #{inspect(reason)}"` and MUST NOT raise or crash the controller process. The HTTP 422 response to the agent is not affected by the broadcast failure.

---

### FR-7.8: schema_violation Node State for Topology

When a `SchemaViolationEvent` is received by the Topology LiveView (subscribed to `"gateway:violations"`), the node corresponding to `event["agent_id"]` in the Topology Map MUST be updated to state `:schema_violation`. In this state, the node MUST be rendered with an orange highlight color in the Canvas renderer (FRD-008). The `:schema_violation` state MUST be a recognized atom in the node state machine alongside `:active`, `:idle`, `:error`, and `:offline`. The Topology LiveView MUST clear the `:schema_violation` state and return the node to its previous state after a configurable timeout (default 30 seconds) or upon receipt of the next valid message from the same `agent_id`.

**Positive path**: Agent `"agent-42"` sends a malformed message. The Topology Map immediately highlights the `"agent-42"` node orange. Thirty seconds later, the node returns to `:idle`. No page refresh is needed.

**Negative path**: If `event["agent_id"]` does not correspond to any known node in the current Topology Map (the agent has never sent a valid message), the LiveView MUST create a ghost node with state `:schema_violation` and `agent_id` as the label rather than silently dropping the event. This ensures violations from previously unseen agents are visible.

---

### FR-7.9: Post-Validation Routing on Success

When `SchemaInterceptor.validate/1` returns `{:ok, %DecisionLog{} = log}`, the controller MUST forward the validated struct to the appropriate PubSub topic before responding. The primary topic for all validated DecisionLog messages MUST be `"gateway:messages"`. The broadcast key MUST be `:decision_log`. The controller MUST respond with HTTP 202 and body `{"status": "accepted", "trace_id": "<log.meta.trace_id>"}` after the broadcast call returns. The Gateway MUST apply the entropy_score overwrite (FR-6.7) to the struct before broadcasting.

**Positive path**: A valid message is received. The Gateway computes entropy, overwrites `log.cognition.entropy_score`, broadcasts `{:decision_log, log}` on `"gateway:messages"`, and responds HTTP 202 with the confirmed `trace_id`. The Topology and Feed LiveViews receive the message within the PubSub delivery window.

**Negative path**: If the PubSub broadcast fails on the success path, the Gateway MUST log a warning and MUST still respond HTTP 202 to the agent. The agent's message was valid and accepted; a delivery failure to downstream subscribers is an internal Observatory concern and MUST NOT cause the agent to retry a valid message.

---

## Out of Scope (Phase 1)

- Bearer token or API key authentication on POST /gateway/messages
- Rate limiting per agent_id on the ingest endpoint
- Streaming or server-sent event responses to agents
- Schema migration tooling for upgrading DecisionLog versions across a live fleet
- Archival of rejected payloads to a dead-letter queue (DLQ handled in FRD-010 for webhook retries, not ingest rejections)
- Credo custom check for Gateway/UI boundary enforcement (Phase 2)

## Related ADRs

- [ADR-013](../../decisions/ADR-013-hypervisor-platform-scope.md) -- Defines the lib/observatory/gateway/ and lib/observatory/mesh/ directory split and the no-cross-import boundary between Gateway and ObservatoryWeb
- [ADR-015](../../decisions/ADR-015-gateway-schema-interceptor.md) -- Specifies the SchemaInterceptor module, validate/1 contract, SchemaViolationEvent fields, raw_payload_hash security policy, and PubSub topic "gateway:violations"
- [ADR-014](../../decisions/ADR-014-decision-log-envelope.md) -- Defines the DecisionLog schema that SchemaInterceptor validates against
- [ADR-018](../../decisions/ADR-018-entropy-score-loop-detection.md) -- Specifies the entropy_score overwrite that occurs on the success path before PubSub broadcast
