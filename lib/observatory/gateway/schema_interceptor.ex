defmodule Observatory.Gateway.SchemaInterceptor do
  @moduledoc """
  Synchronous validation gate for inbound agent messages.

  All modules under `Observatory.Gateway.*` MUST NOT import, alias, or call
  any module under the `ObservatoryWeb.*` namespace. All cross-boundary
  communication MUST occur exclusively via Phoenix PubSub topics. Do not add
  raw payload content to Logger calls -- only `raw_payload_hash` may appear
  in log output.
  """

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
