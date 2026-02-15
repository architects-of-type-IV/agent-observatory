defmodule ObservatoryWeb.EventController do
  use ObservatoryWeb, :controller
  require Logger

  # ETS table for tracking PreToolUse timestamps by tool_use_id
  @tool_start_table :observatory_tool_starts

  def init_tool_tracking do
    if :ets.whereis(@tool_start_table) == :undefined do
      :ets.new(@tool_start_table, [:named_table, :public, :set])
    end
  end

  def create(conn, params) do
    init_tool_tracking()

    payload = params["payload"] || params
    hook_type = params["hook_event_type"] || params["event_type"] || "Stop"

    # Extract fields from the nested payload (the raw hook stdin JSON)
    tool_name = payload["tool_name"]
    tool_use_id = payload["tool_use_id"]
    cwd = payload["cwd"]
    permission_mode = payload["permission_mode"]

    # Compute tool duration for PostToolUse events
    duration_ms = compute_duration(hook_type, tool_use_id)

    # Track PreToolUse start times
    if hook_type == "PreToolUse" && tool_use_id do
      :ets.insert(@tool_start_table, {tool_use_id, System.monotonic_time(:millisecond)})
    end

    event_attrs = %{
      source_app: params["source_app"] || "unknown",
      session_id: params["session_id"] || "unknown",
      hook_event_type: hook_type,
      payload: sanitize_payload(payload),
      summary: params["summary"],
      model_name: params["model_name"],
      tool_name: tool_name,
      tool_use_id: tool_use_id,
      cwd: cwd,
      permission_mode: permission_mode,
      duration_ms: duration_ms
    }

    case Observatory.Events.Event
         |> Ash.Changeset.for_create(:create, event_attrs)
         |> Ash.create() do
      {:ok, event} ->
        maybe_upsert_session(event)
        handle_channel_events(event)

        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "events:stream",
          {:new_event, event}
        )

        conn
        |> put_status(:created)
        |> json(%{ok: true, id: event.id})

      {:error, changeset} ->
        Logger.warning("Failed to create event: #{inspect(changeset)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid event", details: inspect(changeset.errors)})
    end
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

  defp maybe_upsert_session(event) do
    case event.hook_event_type do
      :SessionStart ->
        payload = event.payload

        Observatory.Events.Session
        |> Ash.Changeset.for_create(:create, %{
          session_id: event.session_id,
          source_app: event.source_app,
          agent_type: payload["agent_type"],
          model: payload["model"],
          started_at: DateTime.utc_now()
        })
        |> Ash.create()

      :SessionEnd ->
        case Ash.read(Observatory.Events.Session) do
          {:ok, sessions} ->
            sessions
            |> Enum.find(&(&1.session_id == event.session_id and &1.source_app == event.source_app))
            |> case do
              nil -> :ok
              session -> session |> Ash.Changeset.for_update(:mark_ended) |> Ash.update()
            end

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

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

  defp handle_send_message(event, input) do
    type = input["type"] || "message"
    recipient = input["recipient"]
    content = input["content"] || input["summary"] || ""

    case type do
      "message" when is_binary(recipient) ->
        Observatory.Mailbox.send_message(
          recipient,
          event.session_id,
          content,
          type: :text,
          metadata: %{
            source_app: event.source_app,
            summary: input["summary"]
          }
        )

      "broadcast" ->
        # Broadcast to team (requires team context from event)
        if team_name = input["team_name"] do
          Observatory.Channels.publish_to_team(team_name, %{
            from: event.session_id,
            content: content,
            timestamp: DateTime.utc_now()
          })
        end

      _ ->
        :ok
    end
  end
end
