defmodule ObservatoryWeb.DashboardFeedHelpers do
  @moduledoc """
  Feed grouping and event pairing helpers for the Observatory Dashboard.
  Groups events by session, segments by subagent spans, and pairs tool executions.
  """

  # ═══════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════

  @doc """
  Build grouped feed structure with segments, agent names, and full metadata.
  Each session group contains segments: parent events and subagent blocks.
  """
  def build_feed_groups(events, teams \\ []) do
    name_map = build_agent_name_map(events, teams)

    events
    |> group_events_by_session()
    |> Enum.map(fn {session_id, session_events} ->
      build_session_group(session_id, session_events, name_map)
    end)
    |> Enum.sort_by(& &1.start_time, {:desc, DateTime})
  end

  def get_paired_tool_use_ids(tool_pairs) do
    tool_pairs |> Enum.map(& &1.tool_use_id) |> MapSet.new()
  end

  @feed_hidden_types [
    :SessionStart,
    :SessionEnd,
    :Stop,
    :SubagentStart,
    :SubagentStop,
    :PreCompact
  ]

  def get_standalone_events(events, paired_ids) do
    Enum.reject(events, fn e ->
      (e.tool_use_id && MapSet.member?(paired_ids, e.tool_use_id)) ||
        e.hook_event_type in @feed_hidden_types
    end)
  end

  def elapsed_time_ms(pre_event, now \\ DateTime.utc_now()) do
    DateTime.diff(now, pre_event.inserted_at, :millisecond)
  end

  @doc """
  Build a chronological timeline of tool chains and standalone events.
  Groups consecutive tool pairs into chains for collapsible rendering.

  Returns a list of:
    {:tool_chain, [pair1, pair2, ...]}  -- consecutive tool calls grouped
    {:event, standalone_event}          -- non-tool events (prompts, notifications, etc.)
  """
  def build_segment_timeline(tool_pairs, events) do
    paired_ids = get_paired_tool_use_ids(tool_pairs)
    standalone = get_standalone_events(events, paired_ids)

    tool_items =
      Enum.map(tool_pairs, fn pair ->
        %{type: :tool, data: pair, time: pair.pre.inserted_at}
      end)

    standalone_items =
      Enum.map(standalone, fn event ->
        %{type: :event, data: event, time: event.inserted_at}
      end)

    (tool_items ++ standalone_items)
    |> Enum.sort_by(& &1.time, {:asc, DateTime})
    |> group_into_chains()
  end

  defp group_into_chains(items) do
    items
    |> Enum.reduce([], fn item, acc ->
      case {item.type, acc} do
        {:tool, [{:tool_chain, chain} | rest]} ->
          [{:tool_chain, chain ++ [item.data]} | rest]

        {:tool, _} ->
          [{:tool_chain, [item.data]} | acc]

        {:event, _} ->
          [{:event, item.data} | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Summarize tool names in a chain for the collapsed header.
  Returns string like "Read x3, Edit x1, Bash x1"
  """
  def chain_tool_summary(pairs) do
    pairs
    |> Enum.frequencies_by(& &1.tool_name)
    |> Enum.sort_by(fn {_name, count} -> -count end)
    |> Enum.map(fn {name, count} ->
      if count == 1, do: name, else: "#{name} x#{count}"
    end)
    |> Enum.join(", ")
  end

  @doc """
  Total duration of a tool chain in milliseconds.
  """
  def chain_total_duration(pairs) do
    pairs
    |> Enum.map(& &1.duration_ms)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      durations -> Enum.sum(durations)
    end
  end

  @doc """
  Overall status of a tool chain.
  """
  def chain_status(pairs) do
    cond do
      Enum.any?(pairs, &(&1.status == :in_progress)) -> :in_progress
      Enum.any?(pairs, &(&1.status == :failure)) -> :has_failures
      Enum.all?(pairs, &(&1.status == :success)) -> :success
      true -> :mixed
    end
  end

  # ═══════════════════════════════════════════════════════
  # Session group builder
  # ═══════════════════════════════════════════════════════

  defp group_events_by_session(events) do
    Enum.group_by(events, & &1.session_id)
  end

  defp build_session_group(session_id, events, name_map) do
    sorted = Enum.sort_by(events, & &1.inserted_at, {:asc, DateTime})

    session_start = Enum.find(sorted, &(&1.hook_event_type == :SessionStart))
    session_end = Enum.find(sorted, &(&1.hook_event_type == :SessionEnd))

    first_event = List.first(sorted)
    last_event = List.last(sorted)

    has_subagents = Enum.any?(sorted, &(&1.hook_event_type == :SubagentStart))
    segments = build_segments(sorted)

    # Determine role from segments
    role =
      cond do
        has_subagents -> :lead
        true -> :standalone
      end

    subagent_count =
      segments |> Enum.count(fn s -> s.type == :subagent end)

    total_duration_ms =
      if session_start && session_end,
        do: DateTime.diff(session_end.inserted_at, session_start.inserted_at, :millisecond)

    %{
      session_id: session_id,
      agent_name: Map.get(name_map, session_id),
      role: role,
      events: sorted,
      segments: segments,
      session_start: session_start,
      session_end: session_end,
      stop_event: Enum.find(Enum.reverse(sorted), &(&1.hook_event_type == :Stop)),
      model: extract_model(sorted),
      cwd: extract_cwd(sorted),
      permission_mode: extract_permission_mode(sorted),
      source_app: first_event && first_event.source_app,
      event_count: length(sorted),
      tool_count: sorted |> Enum.count(&(&1.hook_event_type == :PreToolUse)),
      subagent_count: subagent_count,
      total_duration_ms: total_duration_ms,
      start_time:
        if(session_start, do: session_start.inserted_at, else: first_event && first_event.inserted_at),
      end_time:
        cond do
          session_end -> session_end.inserted_at
          true -> last_event && last_event.inserted_at
        end,
      is_active: session_end == nil
    }
  end

  # ═══════════════════════════════════════════════════════
  # Segment builder -- splits session events by subagent spans
  # ═══════════════════════════════════════════════════════

  defp build_segments(sorted_events) do
    spans = extract_subagent_spans(sorted_events)

    if spans == [] do
      # No subagents: single parent segment with all events
      tool_pairs = pair_tool_events(sorted_events)
      [%{type: :parent, events: sorted_events, tool_pairs: tool_pairs}]
    else
      segment_by_spans(sorted_events, spans)
    end
  end

  defp extract_subagent_spans(events) do
    starts =
      events
      |> Enum.filter(&(&1.hook_event_type == :SubagentStart))
      |> Enum.map(fn e ->
        %{
          agent_id: (e.payload || %{})["agent_id"],
          agent_type: (e.payload || %{})["agent_type"],
          event: e,
          time: e.inserted_at
        }
      end)

    stops =
      events
      |> Enum.filter(&(&1.hook_event_type == :SubagentStop))
      |> Enum.map(fn e ->
        %{agent_id: (e.payload || %{})["agent_id"], event: e, time: e.inserted_at}
      end)

    # Match starts to stops by agent_id
    Enum.map(starts, fn start ->
      stop = Enum.find(stops, fn s -> s.agent_id == start.agent_id end)

      %{
        agent_id: start.agent_id,
        agent_type: start.agent_type,
        start_event: start.event,
        stop_event: stop && stop.event,
        start_time: start.time,
        end_time: stop && stop.time
      }
    end)
  end

  defp segment_by_spans(events, spans) do
    # Build a timeline: walk events, track active subagent spans
    # Events before any span = parent
    # Events within a span = subagent
    # Events between spans = parent
    sorted_spans = Enum.sort_by(spans, & &1.start_time, {:asc, DateTime})

    {segments, current_parent_events} =
      Enum.reduce(events, {[], []}, fn event, {segs, parent_acc} ->
        cond do
          # SubagentStart: flush parent events, begin new subagent segment
          event.hook_event_type == :SubagentStart ->
            span = find_span_by_start(sorted_spans, event)
            parent_seg = flush_parent(parent_acc)
            segs = if parent_seg, do: segs ++ [parent_seg], else: segs

            if span do
              # Collect all events between this start and its stop
              subagent_events = collect_span_events(events, span)
              tool_pairs = pair_tool_events(subagent_events)

              sub_seg = %{
                type: :subagent,
                agent_id: span.agent_id,
                agent_type: span.agent_type,
                start_event: span.start_event,
                stop_event: span.stop_event,
                start_time: span.start_time,
                end_time: span.end_time,
                events: subagent_events,
                tool_pairs: tool_pairs,
                event_count: length(subagent_events),
                tool_count: length(tool_pairs)
              }

              {segs ++ [sub_seg], []}
            else
              # Unmatched SubagentStart -- treat as standalone event in parent
              {segs, parent_acc ++ [event]}
            end

          # Skip events that belong to an active subagent span
          event.hook_event_type == :SubagentStop ->
            # SubagentStop already handled by the span; skip in parent
            {segs, parent_acc}

          in_any_span?(event, sorted_spans) ->
            # This event is inside a subagent span, already collected
            {segs, parent_acc}

          true ->
            # Parent event
            {segs, parent_acc ++ [event]}
        end
      end)

    # Flush remaining parent events
    final_parent = flush_parent(current_parent_events)
    if final_parent, do: segments ++ [final_parent], else: segments
  end

  defp find_span_by_start(spans, event) do
    agent_id = (event.payload || %{})["agent_id"]
    Enum.find(spans, fn s -> s.agent_id == agent_id end)
  end

  defp collect_span_events(all_events, span) do
    # Events strictly between SubagentStart and SubagentStop timestamps
    # Exclude the SubagentStart/SubagentStop markers themselves
    all_events
    |> Enum.filter(fn e ->
      e.hook_event_type not in [:SubagentStart, :SubagentStop] &&
        DateTime.compare(e.inserted_at, span.start_time) in [:gt, :eq] &&
        (span.end_time == nil || DateTime.compare(e.inserted_at, span.end_time) in [:lt, :eq])
    end)
  end

  defp in_any_span?(event, spans) do
    # Check if event falls within any subagent span's time range
    Enum.any?(spans, fn span ->
      event.hook_event_type not in [:SubagentStart, :SubagentStop] &&
        DateTime.compare(event.inserted_at, span.start_time) in [:gt, :eq] &&
        (span.end_time == nil || DateTime.compare(event.inserted_at, span.end_time) in [:lt, :eq])
    end)
  end

  defp flush_parent([]), do: nil

  defp flush_parent(events) do
    tool_pairs = pair_tool_events(events)
    %{type: :parent, events: events, tool_pairs: tool_pairs}
  end

  # ═══════════════════════════════════════════════════════
  # Agent name resolution
  # ═══════════════════════════════════════════════════════

  defp build_agent_name_map(events, teams) do
    team_names =
      teams
      |> Enum.flat_map(fn team ->
        (team[:members] || [])
        |> Enum.flat_map(fn m ->
          entries = []
          entries = if m[:session_id], do: [{m[:session_id], m[:name]}] ++ entries, else: entries
          entries = if m[:agent_id], do: [{m[:agent_id], m[:name]}] ++ entries, else: entries
          entries
        end)
      end)
      |> Map.new()

    session_start_names =
      events
      |> Enum.filter(&(&1.hook_event_type == :SessionStart))
      |> Enum.reduce(%{}, fn e, acc ->
        model = (e.payload || %{})["model"] || e.model_name
        source = (e.payload || %{})["source"]
        name = source || model
        if name, do: Map.put(acc, e.session_id, name), else: acc
      end)

    Map.merge(session_start_names, team_names)
  end

  # ═══════════════════════════════════════════════════════
  # Tool pairing
  # ═══════════════════════════════════════════════════════

  defp pair_tool_events(events) do
    post_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type in [:PostToolUse, :PostToolUseFailure] and e.tool_use_id
      end)
      |> Map.new(fn e -> {e.tool_use_id, e} end)

    events
    |> Enum.filter(fn e -> e.hook_event_type == :PreToolUse and e.tool_use_id end)
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

  # ═══════════════════════════════════════════════════════
  # Metadata extraction
  # ═══════════════════════════════════════════════════════

  defp extract_model(events) do
    session_start = Enum.find(events, &(&1.hook_event_type == :SessionStart))

    cond do
      session_start && is_map(session_start.payload) ->
        session_start.payload["model"] || session_start.model_name

      true ->
        Enum.find_value(events, fn e -> e.model_name || (e.payload || %{})["model"] end)
    end
  end

  defp extract_cwd(events) do
    events
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.find_value(fn e -> e.cwd end)
  end

  defp extract_permission_mode(events) do
    events
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.find_value(fn e -> e.permission_mode end)
  end
end
