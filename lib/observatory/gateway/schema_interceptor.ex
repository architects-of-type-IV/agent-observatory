defmodule Observatory.Gateway.SchemaInterceptor do
  @moduledoc """
  Synchronous validation gate for inbound agent messages.

  All modules under `Observatory.Gateway.*` MUST NOT import, alias, or call
  any module under the `ObservatoryWeb.*` namespace. All cross-boundary
  communication MUST occur exclusively via Phoenix PubSub topics. Do not add
  raw payload content to Logger calls -- only `raw_payload_hash` may appear
  in log output.
  """

  require Logger

  alias Observatory.Gateway.EntropyTracker
  alias Observatory.Mesh.DecisionLog

  @spec validate(map()) :: {:ok, DecisionLog.t()} | {:error, Ecto.Changeset.t()}
  def validate(params) when is_map(params) do
    changeset = DecisionLog.changeset(%DecisionLog{}, params)

    if changeset.valid? do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:error, changeset}
    end
  end

  @doc """
  Validates params and enriches the resulting DecisionLog with a Gateway-computed entropy score.

  Calls `validate/1` first. On success, calls `EntropyTracker.record_and_score/2` synchronously
  and overwrites `cognition.entropy_score` with the returned Gateway-authoritative value.

  If entropy computation fails (missing agent registration), the original agent-reported score
  is retained and a warning is logged.

  Returns `{:ok, %DecisionLog{}}` or `{:error, changeset}`.
  """
  @spec validate_and_enrich(map()) :: {:ok, DecisionLog.t()} | {:error, Ecto.Changeset.t()}
  def validate_and_enrich(params) when is_map(params) do
    case validate(params) do
      {:error, changeset} ->
        {:error, changeset}

      {:ok, log} ->
        enrich_with_entropy(log)
    end
  end

  @doc false
  @spec deduplicate_alert(map(), map()) :: map()
  def deduplicate_alert(alerts, %{session_id: sid, entropy_score: score} = event) do
    if Map.has_key?(alerts, sid) do
      Map.update!(alerts, sid, fn existing -> %{existing | entropy_score: score} end)
    else
      Map.put(alerts, sid, event)
    end
  end

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

  # Private

  defp enrich_with_entropy(log) do
    case extract_entropy_fields(log) do
      nil ->
        {:ok, log}

      {session_id, intent, tool_call, action_status} ->
        # Synchronous call per FR-9.9 and ADR-018. Must NOT be Task.async or GenServer.cast.
        case EntropyTracker.record_and_score(session_id, {intent, tool_call, action_status}) do
          {:ok, score, _severity} ->
            {:ok, DecisionLog.put_gateway_entropy_score(log, score)}

          {:error, :missing_agent_id} ->
            Logger.warning(
              "SchemaInterceptor: entropy computation failed for session #{session_id}, retaining agent-reported score"
            )

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

  defp format_first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> flatten_error_paths()
    |> List.first() || "schema validation failed"
  end

  defp flatten_error_paths(errors, prefix \\ nil) do
    Enum.flat_map(errors, fn
      {field, messages} when is_list(messages) ->
        key = if prefix, do: "#{prefix}.#{field}", else: to_string(field)
        ["missing required field: #{key} (#{Enum.join(messages, ", ")})"]

      {field, nested} when is_map(nested) ->
        key = if prefix, do: "#{prefix}.#{field}", else: to_string(field)
        flatten_error_paths(nested, key)
    end)
  end
end
