---
type: phase
id: 2
title: gateway-core
date: 2026-02-22
status: pending
links:
  adr: [ADR-013, ADR-015]
depends_on:
  - phase: 1
---

# Phase 2: Gateway Core

## Overview

This phase builds the complete HTTP ingress layer for the Hypervisor Observatory. The central artifact is `Observatory.Gateway.SchemaInterceptor`, a synchronous validation module that sits between every inbound agent message and the downstream processing pipeline. Every message arriving via `POST /gateway/messages` passes through `SchemaInterceptor.validate/1` before any routing, storage, or PubSub broadcast occurs. Valid messages are entropy-scored and forwarded on `"gateway:messages"`; invalid messages are rejected with HTTP 422, wrapped in a `SchemaViolationEvent`, and broadcast on `"gateway:violations"` so the UI can surface the failure in real time without any page refresh. The raw payload of a rejected message is never stored, logged, or broadcast — only its SHA-256 hash is retained for forensic correlation.

Phase 2 depends on Phase 1 (DecisionLog Schema) because `SchemaInterceptor.validate/1` delegates directly to `Observatory.Mesh.DecisionLog.changeset/2` and returns `{:ok, %DecisionLog{}}` on success. Phase 1 must be complete before any Phase 2 module can compile. The entropy overwrite applied on the success path (`log.cognition.entropy_score`) is also defined against the `DecisionLog.Cognition` embedded schema from Phase 1. The module boundary enforced in this phase — `Observatory.Gateway.*` must never import or alias `ObservatoryWeb.*`, and vice versa — is the architectural seam that allows the Gateway to be extracted to a separate node in a future deployment without restructuring business logic.

### ADR Links

- [ADR-013](../decisions/ADR-013-hypervisor-platform-scope.md) — Hypervisor Platform Scope
- [ADR-015](../decisions/ADR-015-gateway-schema-interceptor.md) — Gateway Schema Interceptor

---

## 2.1 SchemaInterceptor Module & Validation Contract

- [ ] **Section 2.1 Complete**

This section creates `Observatory.Gateway.SchemaInterceptor` and establishes the two foundational contracts it must satisfy: the module boundary constraint (no cross-imports between `Observatory.Gateway.*` and `ObservatoryWeb.*`) and the `validate/1` synchronous contract (delegates to `DecisionLog.changeset/2`, returns a tagged tuple, no async work). Both tasks must pass `mix compile --warnings-as-errors` before any HTTP wiring in Section 2.2 begins.

---

### 2.1.1 Module Location & Boundary

- [ ] **Task 2.1.1 Complete**
- **Governed by:** ADR-013, ADR-015
- **Parent UCs:** UC-0209

Create the `Observatory.Gateway.SchemaInterceptor` module at the required path and document the module boundary constraint in its `@moduledoc`. The module must compile cleanly with no imports or aliases pointing into `ObservatoryWeb.*`. A boundary test confirms the constraint is documented and that the module file does not contain any `ObservatoryWeb` string references outside of the moduledoc description text.

#### Subtasks

- [ ] **2.1.1.1** Create the file `lib/observatory/gateway/schema_interceptor.ex` with `defmodule Observatory.Gateway.SchemaInterceptor do`. Add a `@moduledoc` that states explicitly: "All modules under `Observatory.Gateway.*` MUST NOT import, alias, or call any module under the `ObservatoryWeb.*` namespace. All cross-boundary communication MUST occur exclusively via Phoenix PubSub topics. Do not add raw payload content to Logger calls — only `raw_payload_hash` may appear in log output." Add a `use` or `alias` only for `Observatory.Mesh.DecisionLog` and `Ecto.Changeset`. Do not import or alias any `ObservatoryWeb.*` module.
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.1.1.2** Create the test file `test/observatory/gateway/schema_interceptor_test.exs` and add a test `"SchemaInterceptor @moduledoc documents the module boundary constraint"` that reads the module's `@moduledoc` string via `Observatory.Gateway.SchemaInterceptor.__info__(:module)` and `Code.fetch_docs/1`, asserts the moduledoc string contains the substring `"ObservatoryWeb"`, and asserts the moduledoc string contains the substring `"PubSub"`. This confirms the constraint is documented for future contributors.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only boundary"`

- [ ] **2.1.1.3** In the same test file, add a test `"SchemaInterceptor source file contains no ObservatoryWeb alias or import outside moduledoc"` that reads the source file at `lib/observatory/gateway/schema_interceptor.ex` using `File.read!/1`, strips the moduledoc block content (the string between the first `"""` pair after `@moduledoc`), and asserts the remaining source text does not match the regex `~r/alias ObservatoryWeb|import ObservatoryWeb/`.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only boundary"`

---

### 2.1.2 validate/1 Synchronous Contract

- [ ] **Task 2.1.2 Complete**
- **Governed by:** ADR-015
- **Parent UCs:** UC-0210

Implement `Observatory.Gateway.SchemaInterceptor.validate/1` as a public function that accepts a string-keyed params map, delegates synchronously to `Observatory.Mesh.DecisionLog.changeset/2`, checks `Ecto.Changeset.valid?/1`, and returns either `{:ok, %DecisionLog{}}` or `{:error, %Ecto.Changeset{}}`. The function body must contain no `Task`, `GenServer`, `Process.spawn`, `send`, or `receive` calls. Three tests confirm the positive path, the negative path, and the absence of async primitives.

#### Subtasks

- [ ] **2.1.2.1** In `lib/observatory/gateway/schema_interceptor.ex`, implement:

  ```elixir
  @spec validate(map()) :: {:ok, DecisionLog.t()} | {:error, Ecto.Changeset.t()}
  def validate(params) when is_map(params) do
    changeset = DecisionLog.changeset(%DecisionLog{}, params)
    if Ecto.Changeset.valid?(changeset) do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:error, changeset}
    end
  end
  ```

  The function must call `DecisionLog.changeset/2` directly in the calling process. No `Task.start`, `Task.async`, `GenServer.call`, `send/2`, or `receive` block may appear inside the function body.
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.1.2.2** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"validate/1 returns {:ok, %DecisionLog{}} for a fully valid params map"`. Build a valid string-keyed params map containing all required DecisionLog fields (use the canonical fixture defined in Phase 1 tests if available, or construct one inline). Call `SchemaInterceptor.validate(params)` and assert the return value matches `{:ok, %Observatory.Mesh.DecisionLog{}}`.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only validate"`

- [ ] **2.1.2.3** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"validate/1 returns {:error, changeset} when meta.timestamp is absent"`. Construct a params map that includes all required fields except `meta.timestamp`. Call `SchemaInterceptor.validate(params)` and assert the return value matches `{:error, %Ecto.Changeset{valid?: false}}`. Additionally assert that `changeset.errors` contains an entry for `:timestamp` whose message includes the substring `"can't be blank"`.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only validate"`

- [ ] **2.1.2.4** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"validate/1 completes synchronously with no async primitives in source"`. Read the source of `lib/observatory/gateway/schema_interceptor.ex` via `File.read!/1`. Assert the source does not match `~r/Task\.(start|async)|GenServer\.call|Process\.spawn|:erlang\.spawn/`. This confirms the synchronous contract is preserved by code structure, not just by test behavior.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only validate"`

---

## 2.2 HTTP Endpoint & 422 Rejection

- [ ] **Section 2.2 Complete**

This section wires the HTTP surface: a `:api` pipeline with JSON body parsing, the `POST /gateway/messages` route, and `ObservatoryWeb.GatewayController` with both the success (202) and rejection (422) branches. The controller calls `SchemaInterceptor.validate/1` as its first action. All router and controller changes must compile and all gateway controller tests must pass before proceeding to Section 2.3.

---

### 2.2.1 POST /gateway/messages Route

- [ ] **Task 2.2.1 Complete**
- **Governed by:** ADR-013, ADR-015
- **Parent UCs:** UC-0211

Add an `:api` pipeline to `lib/observatory_web/router.ex` with JSON body parsing and no session/browser authentication plugs. Declare `post "/gateway/messages"` in that pipeline. Create `lib/observatory_web/controllers/gateway_controller.ex` with a `create/2` action stub that calls `SchemaInterceptor.validate/1` first. Confirm that `POST /gateway/message` (singular, no trailing `s`) returns HTTP 404.

#### Subtasks

- [ ] **2.2.1.1** In `lib/observatory_web/router.ex`, add the following pipeline after the existing pipelines (do not modify existing pipelines):

  ```elixir
  pipeline :api do
    plug Plug.Parsers,
      parsers: [:json],
      pass: ["application/json"],
      json_decoder: Jason
    plug :accepts, ["json"]
  end
  ```

  Then add a new scope block:

  ```elixir
  scope "/gateway", ObservatoryWeb do
    pipe_through :api
    post "/messages", GatewayController, :create
  end
  ```

  Do not add `plug :put_secure_browser_headers`, `plug :fetch_session`, or any authentication plug to the `:api` pipeline.
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.2.1.2** Create `lib/observatory_web/controllers/gateway_controller.ex`:

  ```elixir
  defmodule ObservatoryWeb.GatewayController do
    use ObservatoryWeb, :controller

    alias Observatory.Gateway.SchemaInterceptor

    @doc """
    Accepts a DecisionLog JSON payload from an agent, validates it against the
    DecisionLog schema, and either routes it downstream (HTTP 202) or rejects
    it with a structured error body (HTTP 422).

    This controller MUST NOT be called directly from any LiveView module.
    All LiveView interaction with Gateway data occurs via PubSub subscriptions.
    """
    def create(conn, params) do
      case SchemaInterceptor.validate(params) do
        {:ok, log} ->
          handle_valid(conn, log)
        {:error, changeset} ->
          handle_invalid(conn, changeset, params)
      end
    end

    defp handle_valid(conn, _log) do
      # Placeholder: entropy overwrite and PubSub broadcast implemented in Task 2.4.2
      conn
      |> put_status(:accepted)
      |> json(%{"status" => "accepted", "trace_id" => nil})
    end

    defp handle_invalid(conn, changeset, params) do
      # Placeholder: SchemaViolationEvent construction and broadcast in Tasks 2.3.1 and 2.3.2
      detail = format_changeset_errors(changeset)
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        "status" => "rejected",
        "reason" => "schema_violation",
        "detail" => detail,
        "trace_id" => nil
      })
    end

    defp format_changeset_errors(changeset) do
      changeset
      |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {k, v}, acc ->
          String.replace(acc, "%{#{k}}", to_string(v))
        end)
      end)
      |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
      |> List.first()
    end
  end
  ```
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.2.1.3** Create `test/observatory_web/controllers/gateway_controller_test.exs` and add a test `"POST /gateway/message (singular) returns HTTP 404"`. Use `Phoenix.ConnTest` to send `post(conn, "/gateway/message", %{})` and assert `conn.status == 404`. This confirms the router does not match the misspelled path and the controller is never invoked.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only routing"`

- [ ] **2.2.1.4** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"POST /gateway/messages with valid JSON body calls SchemaInterceptor.validate/1 as first action"`. Submit an invalid payload (missing required fields) via `post(conn, "/gateway/messages", %{})` and assert the response status is 422. This confirms `validate/1` is invoked before any other processing — if it were skipped, the response would be something other than 422.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only routing"`

---

### 2.2.2 422 Schema Violation Response

- [ ] **Task 2.2.2 Complete**
- **Governed by:** ADR-015
- **Parent UCs:** UC-0212

Ensure the `handle_invalid/3` branch of `GatewayController` produces a well-formed HTTP 422 response with all four required JSON fields. The `detail` field must be derived from changeset errors. `trace_id` must always be `null` in the 422 case. The response status must be 422, not 400 — tests assert this distinction explicitly.

#### Subtasks

- [ ] **2.2.2.1** In `lib/observatory_web/controllers/gateway_controller.ex`, verify `handle_invalid/3` calls `put_status(:unprocessable_entity)` (which maps to HTTP 422) and `json/2` with a map containing exactly the keys `"status"`, `"reason"`, `"detail"`, and `"trace_id"`. The `"trace_id"` value must be `nil` (serialized as JSON `null`). The `"status"` value must be the string `"rejected"`. The `"reason"` value must be the string `"schema_violation"`. The `format_changeset_errors/1` helper must use `Ecto.Changeset.traverse_errors/2` and return the first formatted error string.
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.2.2.2** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"POST /gateway/messages missing identity.agent_id returns HTTP 422 with structured body"`. Build a params map that contains all required DecisionLog fields except `identity.agent_id`. Post to `/gateway/messages`. Assert response status is 422. Decode the JSON response body and assert: `body["status"] == "rejected"`, `body["reason"] == "schema_violation"`, `body["detail"]` is a non-empty string containing `"agent_id"`, `body["trace_id"] == nil`.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only rejection"`

- [ ] **2.2.2.3** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"POST /gateway/messages schema violation returns 422 not 400"`. Post a syntactically valid JSON payload missing `meta.trace_id`. Assert `conn.status == 422`. Assert `conn.status != 400`. This distinction is critical: HTTP 400 is reserved for malformed JSON that cannot be parsed by `Plug.Parsers`; well-formed JSON that fails schema validation must always produce 422.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only rejection"`

- [ ] **2.2.2.4** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"422 response body trace_id field is null"`. Post a payload missing `meta.trace_id`. Decode the JSON response body. Assert `Map.has_key?(body, "trace_id")` is true and `body["trace_id"] == nil`. This confirms `trace_id` is always present in the response structure, even when its value is null.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only rejection"`

---

## 2.3 SchemaViolationEvent & Security

- [ ] **Section 2.3 Complete**

This section implements two behaviors that must occur on every validation rejection: construction of the `SchemaViolationEvent` plain map (with the raw payload hash security policy enforced) and broadcast of that event on `"gateway:violations"`. These behaviors are implemented in `SchemaInterceptor` as helper functions called by the controller's rejection path. All raw payload security constraints (no logging, no ETS, no `"raw_payload"` key in the event) are enforced by the test suite.

---

### 2.3.1 SchemaViolationEvent Construction

- [ ] **Task 2.3.1 Complete**
- **Governed by:** ADR-015
- **Parent UCs:** UC-0213, UC-0214

Add `Observatory.Gateway.SchemaInterceptor.build_violation_event/3` that takes the changeset, the params map, and the raw body binary (or `nil` when unavailable), and returns a plain Elixir map with exactly six fields. Enforce the security policy: no `"raw_payload"` key, no logging of params, and the hash is always computed and always present.

#### Subtasks

- [ ] **2.3.1.1** In `lib/observatory/gateway/schema_interceptor.ex`, implement:

  ```elixir
  @spec build_violation_event(Ecto.Changeset.t(), map(), binary() | nil) :: map()
  def build_violation_event(changeset, params, raw_body) do
    agent_id = get_in(params, ["identity", "agent_id"]) || "unknown"
    capability_version = get_in(params, ["identity", "capability_version"]) || "unknown"
    violation_reason = format_first_error(changeset)
    raw_payload_hash = compute_hash(raw_body, params)
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      "event_type" => "schema_violation",
      "timestamp" => timestamp,
      "agent_id" => agent_id,
      "capability_version" => capability_version,
      "violation_reason" => violation_reason,
      "raw_payload_hash" => raw_payload_hash
    }
  end

  defp compute_hash(raw_body, params) when is_binary(raw_body) and byte_size(raw_body) > 0 do
    digest = :crypto.hash(:sha256, raw_body)
    "sha256:" <> Base.encode16(digest, case: :lower)
  end

  defp compute_hash(_raw_body, params) do
    json_fallback = Jason.encode!(params)
    digest = :crypto.hash(:sha256, json_fallback)
    "sha256:" <> Base.encode16(digest, case: :lower)
  end

  defp format_first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "missing required field: #{field} (#{Enum.join(errors, ", ")})" end)
    |> List.first() || "schema validation failed"
  end
  ```

  The function must not log the `params` map or `raw_body` at any log level. The returned map must not contain a `"raw_payload"` key.
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.3.1.2** Update `lib/observatory_web/controllers/gateway_controller.ex` to call `SchemaInterceptor.build_violation_event/3` inside `handle_invalid/3`. Pass `changeset`, `params`, and `raw_body` where `raw_body` is obtained from `conn` via a custom body reader or falls back to `nil` (triggering the JSON-fallback hash path in `compute_hash/2`). Replace the inline `format_changeset_errors/1` helper call in `handle_invalid/3` with the `detail` field sourced from `event["violation_reason"]`. Store the event in a local variable named `event` so it can be passed to the PubSub broadcast in Task 2.3.2.

  ```elixir
  defp handle_invalid(conn, changeset, params) do
    raw_body = conn.assigns[:raw_body]  # set by body reader plug, may be nil
    event = SchemaInterceptor.build_violation_event(changeset, params, raw_body)
    # PubSub broadcast added in Task 2.3.2
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      "status" => "rejected",
      "reason" => "schema_violation",
      "detail" => event["violation_reason"],
      "trace_id" => nil
    })
  end
  ```
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.3.1.3** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"build_violation_event/3 returns a plain map with all six required keys"`. Construct a minimal invalid changeset by calling `DecisionLog.changeset(%DecisionLog{}, %{})`. Call `SchemaInterceptor.build_violation_event(changeset, %{"identity" => %{"agent_id" => "agent-42", "capability_version" => "1.0.0"}}, "raw-body-bytes")`. Assert the result is a map (not a struct). Assert `Map.keys(result)` contains all of: `"event_type"`, `"timestamp"`, `"agent_id"`, `"capability_version"`, `"violation_reason"`, `"raw_payload_hash"`. Assert `result["event_type"] == "schema_violation"`. Assert `result["agent_id"] == "agent-42"`. Assert `result["capability_version"] == "1.0.0"`.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only violation_event"`

- [ ] **2.3.1.4** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"build_violation_event/3 defaults agent_id to unknown when identity block is absent"`. Call `build_violation_event` with params `%{}` (no identity block). Assert `result["agent_id"] == "unknown"`. Assert `result["capability_version"] == "unknown"`. Assert event construction completes without raising.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only violation_event"`

- [ ] **2.3.1.5** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"build_violation_event/3 raw_payload_hash starts with sha256: and is 71 characters"`. Call `build_violation_event` with `raw_body = "test-body-content"`. Assert `String.starts_with?(result["raw_payload_hash"], "sha256:")`. Assert `String.length(result["raw_payload_hash"]) == 71` (7 chars for `"sha256:"` prefix + 64 chars for lowercase hex SHA-256).
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only violation_event"`

- [ ] **2.3.1.6** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"build_violation_event/3 does not include a raw_payload key in the event map"`. Call `build_violation_event` with a non-nil `raw_body`. Assert `Map.has_key?(result, "raw_payload") == false`. Assert `Map.has_key?(result, :raw_payload) == false`. This test enforces the security policy that prohibits raw payload content in the broadcast event.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only violation_event"`

- [ ] **2.3.1.7** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"build_violation_event/3 falls back to JSON hash when raw_body is nil"`. Call `build_violation_event` with `raw_body = nil` and `params = %{"identity" => %{"agent_id" => "agent-99"}}`. Assert `String.starts_with?(result["raw_payload_hash"], "sha256:")`. Assert `String.length(result["raw_payload_hash"]) == 71`. The hash is computed from `Jason.encode!(params)` in this path; assert it is non-empty.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only violation_event"`

- [ ] **2.3.1.8** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"build_violation_event/3 does not log params or raw body during rejection"`. Use `ExUnit.CaptureLog` to capture all log output during a `build_violation_event` call. Provide a params map with distinctive string values (e.g., `%{"identity" => %{"agent_id" => "SENTINEL-VALUE-12345"}}`). After the call, assert the captured log output does not contain the string `"SENTINEL-VALUE-12345"`. This confirms no param field values are emitted to the log stream.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only violation_event"`

---

### 2.3.2 PubSub Broadcast on gateway:violations

- [ ] **Task 2.3.2 Complete**
- **Governed by:** ADR-015
- **Parent UCs:** UC-0215

Add the PubSub broadcast call to the rejection path in `GatewayController`. The broadcast must use `Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:violations", {:schema_violation, event})`. On broadcast failure, emit a warning log and do not raise. The HTTP 422 response to the agent is never blocked by the broadcast outcome.

#### Subtasks

- [ ] **2.3.2.1** In `lib/observatory_web/controllers/gateway_controller.ex`, update `handle_invalid/3` to perform the PubSub broadcast after the event is constructed and after the HTTP response has been initiated. Use `Task.start/1` to run the broadcast concurrently so the 422 response is not delayed:

  ```elixir
  defp handle_invalid(conn, changeset, params) do
    raw_body = conn.assigns[:raw_body]
    event = SchemaInterceptor.build_violation_event(changeset, params, raw_body)

    Task.start(fn ->
      case Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:violations", {:schema_violation, event}) do
        :ok -> :ok
        {:error, reason} ->
          require Logger
          Logger.warning("Failed to broadcast schema_violation event: #{inspect(reason)}")
      end
    end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      "status" => "rejected",
      "reason" => "schema_violation",
      "detail" => event["violation_reason"],
      "trace_id" => nil
    })
  end
  ```
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.3.2.2** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"broadcast on gateway:violations delivers {:schema_violation, event} to subscribers"`. Subscribe the test process to `"gateway:violations"` via `Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:violations")`. Construct an invalid params map and call `SchemaInterceptor.validate/1` then `build_violation_event/3`, then call `Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:violations", {:schema_violation, event})` directly. Assert the test process receives `{:schema_violation, received_event}` via `assert_receive`. Assert `received_event["agent_id"]` matches the value in the params map.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only pubsub"`

- [ ] **2.3.2.3** In `test/observatory_web/controllers/gateway_controller_test.exs`, add an integration test `"POST /gateway/messages with invalid payload broadcasts {:schema_violation, event} on gateway:violations"`. Subscribe the test process to `"gateway:violations"`. Post an invalid payload to `/gateway/messages`. Assert the response is 422. Use `assert_receive {:schema_violation, event}, 1000` to assert the broadcast arrived. Assert `event["event_type"] == "schema_violation"`.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only pubsub"`

- [ ] **2.3.2.4** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"broadcast uses :schema_violation atom as the message tuple key"`. Subscribe the test process to `"gateway:violations"`. Broadcast a test event. Use pattern matching in `assert_receive {:schema_violation, _event}, 500`. Confirm the test receives `{:schema_violation, _}` and not `{"schema_violation", _}` or `{:violation, _}`. The atom key is required so LiveView `handle_info/2` can pattern-match correctly.
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only pubsub"`

- [ ] **2.3.2.5** In `test/observatory/gateway/schema_interceptor_test.exs`, add a test `"broadcast failure logs a warning and does not raise"`. Use `ExUnit.CaptureLog` to capture log output. Attempt to broadcast on a topic that does not have `Observatory.PubSub` running by calling `Phoenix.PubSub.broadcast(:nonexistent_pubsub_for_test, "gateway:violations", {:schema_violation, %{}})` wrapped in a try/rescue. Assert no exception propagates. Confirm a `Logger.warning` with the text `"Failed to broadcast schema_violation event"` would be emitted by the `handle_invalid/3` branch by reviewing the source code manually (the warning is in a `Task.start/1` so it is non-blocking and cannot be directly captured in a conn-based test without additional tooling).
  - `done_when: "mix test test/observatory/gateway/schema_interceptor_test.exs --only pubsub"`

---

## 2.4 Topology Node State & Post-Validation Routing

- [ ] **Section 2.4 Complete**

This section handles two behaviors: what the topology subscriber layer must do when it receives a `SchemaViolationEvent` (node state transition to `:schema_violation` with orange highlight and 30-second clearance timer), and what the controller must do on the success path (entropy overwrite via `EntropyTracker.record_and_score/2`, PubSub broadcast on `"gateway:messages"`, HTTP 202 with confirmed `trace_id`). These tasks complete the full Gateway Core lifecycle.

---

### 2.4.1 Topology Node State on Violation

- [ ] **Task 2.4.1 Complete**
- **Governed by:** ADR-015, ADR-016
- **Parent UCs:** UC-0216

Broadcast a topology update on `"gateway:topology"` when a schema violation is processed, setting the offending node state to `:schema_violation`. This broadcast enables the Canvas renderer (implemented in Phase 3) to apply the orange highlight (`#f97316` per ADR-016) to the node. The node state `:schema_violation` must be recognized alongside `:active`, `:idle`, `:error`, `:offline`, and `:blocked`. The broadcast must also include a clearance timer instruction so downstream topology subscribers know to revert after 30 seconds.

#### Subtasks

- [ ] **2.4.1.1** In `lib/observatory_web/controllers/gateway_controller.ex`, update `handle_invalid/3` to broadcast a second PubSub message on `"gateway:topology"` after constructing the `SchemaViolationEvent`. Use a separate `Task.start/1` so neither broadcast blocks the HTTP response:

  ```elixir
  Task.start(fn ->
    topology_update = %{
      agent_id: event["agent_id"],
      state: :schema_violation,
      clear_after_ms: 30_000,
      timestamp: event["timestamp"]
    }
    case Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:topology", {:node_state_update, topology_update}) do
      :ok -> :ok
      {:error, reason} ->
        require Logger
        Logger.warning("Failed to broadcast topology node_state_update: #{inspect(reason)}")
    end
  end)
  ```

  This broadcast fires on every schema rejection. The topology subscriber (implemented in Phase 3 / Phase 5) consumes `{:node_state_update, %{agent_id: _, state: :schema_violation, clear_after_ms: 30_000}}` from `"gateway:topology"`.
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.4.1.2** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"POST /gateway/messages with invalid payload broadcasts {:node_state_update, update} on gateway:topology"`. Subscribe the test process to `"gateway:topology"`. Post an invalid payload to `/gateway/messages`. Assert response is 422. Use `assert_receive {:node_state_update, update}, 1000`. Assert `update.state == :schema_violation`. Assert `update.clear_after_ms == 30_000`. Assert `is_binary(update.agent_id)`.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only topology"`

- [ ] **2.4.1.3** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"topology broadcast fires on rejection with :schema_violation state atom not string"`. Subscribe to `"gateway:topology"`. Post an invalid payload. `assert_receive {:node_state_update, update}, 1000`. Assert `update.state == :schema_violation`. Assert `is_atom(update.state)`. Assert `update.state != "schema_violation"`. The state must be an atom to match the node state machine used by the Canvas renderer.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only topology"`

- [ ] **2.4.1.4** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"topology broadcast does NOT fire on successful validation"`. Subscribe to `"gateway:topology"`. Post a fully valid payload to `/gateway/messages`. Assert response is 202. Use `refute_receive {:node_state_update, %{state: :schema_violation}}, 500`. Confirms that topology violation broadcasts are exclusive to the rejection path.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only topology"`

---

### 2.4.2 Post-Validation Message Routing

- [ ] **Task 2.4.2 Complete**
- **Governed by:** ADR-015
- **Parent UCs:** UC-0217

Complete the success path in `GatewayController.handle_valid/2`. Call `EntropyTracker.record_and_score/2` if `log.cognition` is not `nil`, overwrite `log.cognition.entropy_score` with the computed score, broadcast `{:decision_log, updated_log}` on `"gateway:messages"`, and respond HTTP 202 with `{"status": "accepted", "trace_id": "<log.meta.trace_id>"}`. On broadcast failure, log a warning and still respond 202.

#### Subtasks

- [ ] **2.4.2.1** In `lib/observatory_web/controllers/gateway_controller.ex`, replace the placeholder `handle_valid/2` with the full implementation:

  ```elixir
  defp handle_valid(conn, log) do
    updated_log =
      if log.cognition != nil do
        score = Observatory.Mesh.EntropyTracker.record_and_score(log.identity.agent_id, log.cognition.entropy_score)
        put_in(log.cognition.entropy_score, score)
      else
        log
      end

    Task.start(fn ->
      case Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:messages", {:decision_log, updated_log}) do
        :ok -> :ok
        {:error, reason} ->
          require Logger
          Logger.warning("Failed to broadcast decision_log: #{inspect(reason)}")
      end
    end)

    trace_id = updated_log.meta && updated_log.meta.trace_id

    conn
    |> put_status(:accepted)
    |> json(%{"status" => "accepted", "trace_id" => trace_id})
  end
  ```

  If `Observatory.Mesh.EntropyTracker` is not yet implemented (Phase 3), stub it temporarily with a module that exports `record_and_score/2` returning the input score unchanged:

  ```elixir
  # lib/observatory/mesh/entropy_tracker.ex (stub — replace in Phase 3)
  defmodule Observatory.Mesh.EntropyTracker do
    def record_and_score(_agent_id, score), do: score
  end
  ```
  - `done_when: "mix compile --warnings-as-errors"`

- [ ] **2.4.2.2** In `test/observatory_web/controllers/gateway_controller_test.exs`, add an integration test `"POST /gateway/messages with valid payload returns HTTP 202 with trace_id"`. Build a fully valid DecisionLog params map including `meta.trace_id`. Post to `/gateway/messages`. Assert response status is 202. Decode the JSON response body. Assert `body["status"] == "accepted"`. Assert `body["trace_id"]` is a non-nil string matching the `trace_id` value from the submitted params.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only success"`

- [ ] **2.4.2.3** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"POST /gateway/messages with valid payload broadcasts {:decision_log, log} on gateway:messages"`. Subscribe the test process to `"gateway:messages"`. Post a fully valid payload. Assert response is 202. Use `assert_receive {:decision_log, received_log}, 1000`. Assert `received_log` is a `%Observatory.Mesh.DecisionLog{}` struct. Assert `received_log.meta.trace_id` matches the submitted `trace_id`.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only success"`

- [ ] **2.4.2.4** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"schema-rejected payload never broadcasts on gateway:messages"`. Subscribe the test process to `"gateway:messages"`. Post an invalid payload (missing required field). Assert response is 422. Use `refute_receive {:decision_log, _}, 500`. Confirms rejected payloads are completely isolated from the downstream message routing topic.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only success"`

- [ ] **2.4.2.5** In `test/observatory_web/controllers/gateway_controller_test.exs`, add a test `"gateway:messages broadcast failure on success path still returns HTTP 202"`. This test can be implemented by posting a valid payload when the PubSub is unavailable (use a test-only PubSub name that is not started) or by verifying via code inspection that the broadcast is wrapped in a `Task.start/1` and the controller does not pattern-match on the broadcast return value before calling `json/2`. Assert response is 202 and a warning log is emitted when the broadcast fails. Use `ExUnit.CaptureLog` to assert the warning text contains `"Failed to broadcast decision_log"`.
  - `done_when: "mix test test/observatory_web/controllers/gateway_controller_test.exs --only success"`

- [ ] **2.4.2.6** Run the full gateway test suite to confirm all sections pass together. Then run the full project build to confirm zero warnings across all files modified in Phase 2.

  ```bash
  mix test test/observatory/gateway/schema_interceptor_test.exs
  mix test test/observatory_web/controllers/gateway_controller_test.exs
  mix compile --warnings-as-errors
  ```

  All three commands must exit with status 0 before Phase 2 is marked complete.
  - `done_when: "mix test test/observatory/gateway/ test/observatory_web/controllers/gateway_controller_test.exs && mix compile --warnings-as-errors"`
