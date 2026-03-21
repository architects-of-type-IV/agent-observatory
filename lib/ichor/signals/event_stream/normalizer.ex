defmodule Ichor.Signals.EventStream.Normalizer do
  @moduledoc """
  Pure event normalization pipeline. Transforms raw hook event maps into
  canonical event structs.

  All functions here are pure transformations -- no IO, no ETS, no signals.
  The only exceptions are `resolve_session_id/2` and `track_tool_start/1`,
  which touch ETS tables; those remain in EventStream where the table
  references live.
  """

  @hook_event_type_map %{
    "SessionStart" => :SessionStart,
    "SessionEnd" => :SessionEnd,
    "UserPromptSubmit" => :UserPromptSubmit,
    "PreToolUse" => :PreToolUse,
    "PostToolUse" => :PostToolUse,
    "PostToolUseFailure" => :PostToolUseFailure,
    "PermissionRequest" => :PermissionRequest,
    "Notification" => :Notification,
    "SubagentStart" => :SubagentStart,
    "SubagentStop" => :SubagentStop,
    "Stop" => :Stop,
    "PreCompact" => :PreCompact,
    "TaskCompleted" => :TaskCompleted
  }

  @doc """
  Build a normalized event map from raw attrs.

  The `session_id` is resolved by the caller via `resolve_session_id/2`
  (which touches ETS) and passed in as `resolved_session_id`.
  """
  @spec build_event(map(), String.t()) :: map()
  def build_event(attrs, resolved_session_id) do
    now = DateTime.utc_now()
    tmux_session = get_field(attrs, :tmux_session)

    %{
      id: Ash.UUID.generate(),
      source_app: get_field(attrs, :source_app) || "unknown",
      session_id: resolved_session_id,
      hook_event_type: coerce_hook_type(get_field(attrs, :hook_event_type)),
      payload: get_field(attrs, :payload) || %{},
      summary: get_field(attrs, :summary),
      model_name: get_field(attrs, :model_name),
      tool_name: get_field(attrs, :tool_name),
      tool_use_id: get_field(attrs, :tool_use_id),
      cwd: get_field(attrs, :cwd),
      permission_mode: get_field(attrs, :permission_mode),
      duration_ms: get_field(attrs, :duration_ms),
      tmux_session: tmux_session,
      os_pid: get_field(attrs, :os_pid),
      inserted_at: now,
      updated_at: now
    }
  end

  @doc "Enrich attrs with duration_ms if this is a PostToolUse event and a start time is given."
  @spec put_duration(map(), non_neg_integer() | nil) :: map()
  def put_duration(attrs, nil), do: attrs

  def put_duration(%{hook_event_type: type} = attrs, start_time)
      when type in ["PostToolUse", "PostToolUseFailure"] do
    Map.put(attrs, :duration_ms, System.monotonic_time(:millisecond) - start_time)
  end

  def put_duration(attrs, _start_time), do: attrs

  @doc "Remove tool_response and truncate large tool_input values from a payload map."
  @spec sanitize_payload(map() | term()) :: map() | term()
  def sanitize_payload(payload) when is_map(payload) do
    payload
    |> Map.delete("tool_response")
    |> truncate_tool_input()
  end

  def sanitize_payload(payload), do: payload

  @doc "Truncate binary values in tool_input that exceed 500 bytes."
  @spec truncate_tool_input(map()) :: map()
  def truncate_tool_input(%{"tool_input" => input} = payload) when is_map(input) do
    truncated =
      Map.new(input, fn
        {k, v} when is_binary(v) and byte_size(v) > 500 ->
          {k, String.slice(v, 0, 500) <> "...[truncated]"}

        pair ->
          pair
      end)

    Map.put(payload, "tool_input", truncated)
  end

  def truncate_tool_input(payload), do: payload

  @doc "Coerce a hook event type string or atom to a canonical atom."
  @spec coerce_hook_type(String.t() | atom() | term()) :: atom()
  def coerce_hook_type(t) when is_atom(t), do: t

  def coerce_hook_type(t) when is_binary(t) do
    Map.get(@hook_event_type_map, t, :unknown)
  end

  def coerce_hook_type(_), do: :Stop

  @doc "Safe field access that checks both atom and string keys."
  @spec get_field(map(), atom()) :: term()
  def get_field(attrs, key) do
    attrs[key] || attrs[Atom.to_string(key)]
  end
end
