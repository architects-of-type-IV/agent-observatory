defmodule Ichor.Signals.SchemaInterceptor do
  @moduledoc """
  Synchronous validation gate for inbound agent messages.

  This module MUST NOT import, alias, or call
  any module under the `IchorWeb.*` namespace. All cross-boundary
  communication MUST occur exclusively via Phoenix PubSub topics. Do not add
  raw payload content to Logger calls -- only `raw_payload_hash` may appear
  in log output.
  """

  require Logger

  alias Ichor.Mesh.DecisionLog
  alias Ichor.Mesh.DecisionLog.Helpers, as: DLHelpers

  @doc """
  Parses params into a DecisionLog.

  Returns `{:ok, %DecisionLog{}}`.
  """
  @spec validate_and_enrich(map()) :: {:ok, DecisionLog.t()}
  def validate_and_enrich(params) when is_map(params) do
    DLHelpers.from_json(params)
  end

  @doc "Build a schema violation audit event map from an error reason, params, and optional raw body."
  @spec build_violation_event(String.t(), map(), binary() | nil) :: map()
  def build_violation_event(reason, params, raw_body) do
    agent_id = get_in(params, ["identity", "agent_id"]) || "unknown"
    capability_version = get_in(params, ["identity", "capability_version"]) || "unknown"
    raw_payload_hash = compute_hash(raw_body, params)
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      "event_type" => "schema_violation",
      "timestamp" => timestamp,
      "agent_id" => agent_id,
      "capability_version" => capability_version,
      "violation_reason" => reason,
      "raw_payload_hash" => raw_payload_hash
    }
  end

  defp compute_hash(raw_body, _params) when is_binary(raw_body) and byte_size(raw_body) > 0 do
    digest = :crypto.hash(:sha256, raw_body)
    "sha256:" <> Base.encode16(digest, case: :lower)
  end

  defp compute_hash(_raw_body, params) do
    json_fallback = Jason.encode!(params)
    digest = :crypto.hash(:sha256, json_fallback)
    "sha256:" <> Base.encode16(digest, case: :lower)
  end
end
