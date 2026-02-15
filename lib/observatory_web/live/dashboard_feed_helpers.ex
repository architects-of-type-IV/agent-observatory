defmodule ObservatoryWeb.DashboardFeedHelpers do
  @moduledoc """
  Feed grouping and event pairing helpers for the Observatory Dashboard.
  Groups events by session and pairs tool executions (PreToolUse + PostToolUse).
  """

  defp group_events_by_session(events) do
    events
    |> Enum.group_by(& &1.session_id)
  end

  defp pair_tool_events(events) do
    # Create lookup for PostToolUse events by tool_use_id
    post_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type in [:PostToolUse, :PostToolUseFailure] and e.tool_use_id
      end)
      |> Map.new(fn e -> {e.tool_use_id, e} end)

    # Find all PreToolUse events and match with Post events
    events
    |> Enum.filter(fn e ->
      e.hook_event_type == :PreToolUse and e.tool_use_id
    end)
    |> Enum.map(fn pre ->
      post = Map.get(post_events, pre.tool_use_id)

      %{
        pre: pre,
        post: post,
        duration_ms: if(post, do: post.duration_ms, else: nil),
        status: determine_status(post),
        tool_use_id: pre.tool_use_id,
        tool_name: pre.tool_name
      }
    end)
  end

  defp determine_status(nil), do: :in_progress
  defp determine_status(%{hook_event_type: :PostToolUse}), do: :success
  defp determine_status(%{hook_event_type: :PostToolUseFailure}), do: :failure
  defp determine_status(_), do: :unknown

  @doc """
  Build grouped feed structure combining session groups and tool pairs.
  Returns list of session groups with enriched metadata.

  Each group contains:
  - session_id
  - events (chronological)
  - tool_pairs (list of paired tool executions)
  - session_start (SessionStart event or nil)
  - session_end (SessionEnd event or nil)
  - model (extracted from SessionStart)
  - cwd (extracted from events)
  - event_count
  """
  def build_feed_groups(events, _now \\ DateTime.utc_now()) do
    events
    |> group_events_by_session()
    |> Enum.map(fn {session_id, session_events} ->
      sorted_events = Enum.sort_by(session_events, & &1.inserted_at, {:asc, DateTime})

      session_start = Enum.find(sorted_events, &(&1.hook_event_type == :SessionStart))
      session_end = Enum.find(sorted_events, &(&1.hook_event_type == :SessionEnd))

      tool_pairs = pair_tool_events(sorted_events)

      # Calculate total duration
      total_duration_ms =
        if session_start && session_end do
          DateTime.diff(session_end.inserted_at, session_start.inserted_at, :millisecond)
        else
          nil
        end

      %{
        session_id: session_id,
        events: sorted_events,
        tool_pairs: tool_pairs,
        session_start: session_start,
        session_end: session_end,
        model: extract_model(session_start),
        cwd: extract_cwd(sorted_events),
        event_count: length(sorted_events),
        total_duration_ms: total_duration_ms,
        start_time:
          if(session_start,
            do: session_start.inserted_at,
            else: List.first(sorted_events).inserted_at
          ),
        is_active: session_end == nil
      }
    end)
    |> Enum.sort_by(& &1.start_time, {:desc, DateTime})
  end

  defp extract_model(nil), do: nil

  defp extract_model(%{payload: payload}) when is_map(payload) do
    payload["model"]
  end

  defp extract_model(_), do: nil

  defp extract_cwd(events) do
    events
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.find_value(fn e -> e.cwd end)
  end

  @doc """
  Get list of tool_use_ids from paired events to detect which events are part of tool pairs.
  Used for rendering to avoid duplicate display.
  """
  def get_paired_tool_use_ids(tool_pairs) do
    tool_pairs
    |> Enum.map(& &1.tool_use_id)
    |> MapSet.new()
  end

  @doc """
  Check if event is part of a tool pair (should be rendered as part of tool_execution_block).
  """
  def is_paired_event?(event, paired_ids) do
    event.tool_use_id && MapSet.member?(paired_ids, event.tool_use_id)
  end

  @doc """
  Get events that are NOT part of tool pairs (standalone events).
  These should be rendered individually.
  """
  def get_standalone_events(events, paired_ids) do
    events
    |> Enum.reject(&is_paired_event?(&1, paired_ids))
  end

  @doc """
  Calculate elapsed time for in-progress tools.
  """
  def elapsed_time_ms(pre_event, now \\ DateTime.utc_now()) do
    DateTime.diff(now, pre_event.inserted_at, :millisecond)
  end
end
