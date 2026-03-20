defmodule Ichor.Gateway.SchemaInterceptor do
  @moduledoc """
  Synchronous validation gate for inbound agent messages.

  All modules under `Ichor.Gateway.*` MUST NOT import, alias, or call
  any module under the `IchorWeb.*` namespace. All cross-boundary
  communication MUST occur exclusively via Phoenix PubSub topics. Do not add
  raw payload content to Logger calls -- only `raw_payload_hash` may appear
  in log output.
  """

  require Logger

  alias Ichor.Gateway.EntropyTracker
  alias Ichor.Mesh.DecisionLog
  alias Ichor.Mesh.DecisionLog.Helpers, as: DLHelpers

  @doc """
  Parses params into a DecisionLog and enriches it with a Gateway-computed entropy score.

  Calls `DecisionLog.Helpers.from_json/1` first. On success, calls
  `EntropyTracker.record_and_score/2` synchronously and overwrites
  `cognition.entropy_score` with the returned Gateway-authoritative value.

  If entropy computation fails (missing agent registration), the original
  agent-reported score is retained.

  Returns `{:ok, %DecisionLog{}}`.
  """
  @spec validate_and_enrich(map()) :: {:ok, DecisionLog.t()}
  def validate_and_enrich(params) when is_map(params) do
    {:ok, log} = DLHelpers.from_json(params)
    enrich_with_entropy(log)
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

  defp enrich_with_entropy(log) do
    case extract_entropy_fields(log) do
      nil ->
        {:ok, log}

      {session_id, intent, tool_call, action_status} ->
        # Synchronous call per FR-9.9 and ADR-018. Must NOT be Task.async or GenServer.cast.
        case EntropyTracker.record_and_score(session_id, {intent, tool_call, action_status}) do
          {:ok, score, _severity} ->
            {:ok, DLHelpers.put_gateway_entropy_score(log, score)}

          _ ->
            {:ok, log}
        end
    end
  end

  defp extract_entropy_fields(%{
         meta: %{trace_id: session_id},
         cognition: %{intent: intent},
         action: %{tool_call: tool_call, status: action_status}
       })
       when is_binary(session_id) and is_binary(intent) do
    {session_id, intent, tool_call, action_status}
  end

  defp extract_entropy_fields(_), do: nil

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
