defmodule ObservatoryWeb.EventController do
  use ObservatoryWeb, :controller
  require Logger

  # ETS table for tracking PreToolUse timestamps by tool_use_id
  @tool_start_table :observatory_tool_starts

  def init_tool_tracking do
    try do
      :ets.new(@tool_start_table, [:named_table, :public, :set])
    rescue
      ArgumentError -> :ok
    end
  end

  def create(conn, params) do
    init_tool_tracking()

    # Support both new format (raw: full stdin JSON) and legacy (payload: extracted)
    {raw, hook_type, source_app, tmux_session} = extract_envelope(params)

    # Extract fields from the raw hook stdin JSON
    tool_name = raw["tool_name"]
    tool_use_id = raw["tool_use_id"]
    cwd = raw["cwd"]
    permission_mode = raw["permission_mode"]
    session_id = raw["session_id"] || params["session_id"] || "unknown"
    model_name = raw["model"] || raw["model_name"] || params["model_name"]
    summary = raw["summary"] || params["summary"]

    # Compute tool duration for PostToolUse events
    duration_ms = compute_duration(hook_type, tool_use_id)

    # Track PreToolUse start times
    if hook_type == "PreToolUse" && tool_use_id do
      :ets.insert(@tool_start_table, {tool_use_id, System.monotonic_time(:millisecond)})
    end

    event_attrs = %{
      source_app: source_app,
      session_id: session_id,
      hook_event_type: hook_type,
      payload: sanitize_payload(raw),
      summary: summary,
      model_name: model_name,
      tool_name: tool_name,
      tool_use_id: tool_use_id,
      cwd: cwd,
      permission_mode: permission_mode,
      duration_ms: duration_ms,
      tmux_session: tmux_session
    }

    # Non-blocking: buffer for async DB write, broadcast immediately
    {:ok, event} = Observatory.EventBuffer.ingest(event_attrs)

    handle_channel_events(event)

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "events:stream",
      {:new_event, event}
    )

    # Feed event into the unified Gateway pipeline
    Observatory.Gateway.Router.ingest(event)

    conn
    |> put_status(:created)
    |> json(%{ok: true, id: event.id})
  end

  # Strip large fields (tool_response, tool_input file contents) to avoid DB bloat
  defp sanitize_payload(payload) when is_map(payload) do
    payload
    |> Map.delete("tool_response")
    |> truncate_tool_input()
  end

  defp sanitize_payload(payload), do: payload

  defp truncate_tool_input(%{"tool_input" => input} = payload) when is_map(input) do
    truncated =
      Map.new(input, fn
        {k, v} when is_binary(v) and byte_size(v) > 500 ->
          {k, String.slice(v, 0, 500) <> "...[truncated]"}

        pair ->
          pair
      end)

    Map.put(payload, "tool_input", truncated)
  end

  defp truncate_tool_input(payload), do: payload

  defp compute_duration(hook_type, tool_use_id)
       when hook_type in ["PostToolUse", "PostToolUseFailure"] and is_binary(tool_use_id) do
    case :ets.lookup(@tool_start_table, tool_use_id) do
      [{^tool_use_id, start_time}] ->
        :ets.delete(@tool_start_table, tool_use_id)
        System.monotonic_time(:millisecond) - start_time

      _ ->
        nil
    end
  end

  defp compute_duration(_, _), do: nil

  defp handle_channel_events(event) do
    case event.hook_event_type do
      :SessionStart ->
        Observatory.Channels.create_agent_channel(event.session_id)

      :PreToolUse ->
        handle_pre_tool_use(event)

      _ ->
        :ok
    end
  end

  defp handle_pre_tool_use(event) do
    input = (event.payload || %{})["tool_input"] || %{}

    case event.tool_name do
      "TeamCreate" ->
        if team_name = input["team_name"] do
          Observatory.Channels.create_team_channel(team_name, [])
        end

      "SendMessage" ->
        handle_send_message(event, input)

      _ ->
        :ok
    end
  end

  # New format: {hook_event_type, tmux_session, source_app, raw: {...}}
  # Legacy format: {hook_event_type, session_id, source_app, payload: {...}}
  defp extract_envelope(%{"raw" => raw} = params) do
    {
      raw,
      params["hook_event_type"] || "Stop",
      params["source_app"] || "unknown",
      nullify_empty(params["tmux_session"])
    }
  end

  defp extract_envelope(params) do
    payload = params["payload"] || params

    {
      payload,
      params["hook_event_type"] || params["event_type"] || "Stop",
      params["source_app"] || "unknown",
      nullify_empty(params["tmux_session"])
    }
  end

  defp nullify_empty(""), do: nil
  defp nullify_empty(v), do: v

  defp handle_send_message(event, input) do
    type = input["type"] || "message"
    recipient = input["recipient"]
    content = input["content"] || input["summary"] || ""

    payload = %{
      content: content,
      from: event.session_id,
      type: :text,
      metadata: %{
        source_app: event.source_app,
        summary: input["summary"],
        via: :hook_intercept
      }
    }

    case type do
      "message" when is_binary(recipient) ->
        Observatory.Gateway.Router.broadcast("agent:#{recipient}", payload)

      "broadcast" ->
        if team_name = input["team_name"] do
          Observatory.Gateway.Router.broadcast("team:#{team_name}", payload)
        end

      "shutdown_request" when is_binary(recipient) ->
        Observatory.Gateway.Router.broadcast("agent:#{recipient}", payload)

      _ ->
        :ok
    end
  end
end
