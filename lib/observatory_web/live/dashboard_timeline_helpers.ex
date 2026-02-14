defmodule ObservatoryWeb.DashboardTimelineHelpers do
  @moduledoc """
  Timeline computation helpers for the Observatory Dashboard.
  Converts events into timeline blocks for swimlane visualization.
  """

  @doc """
  Compute timeline data from events grouped by session.
  Returns a list of session timelines with blocks.
  """
  def compute_timeline_data(events) do
    # Group events by session
    events
    |> Enum.group_by(& &1.session_id)
    |> Enum.map(fn {session_id, session_events} ->
      sorted_events = Enum.sort_by(session_events, & &1.inserted_at, {:asc, DateTime})

      blocks = build_timeline_blocks(sorted_events)

      first_event = List.first(sorted_events)
      last_event = List.last(sorted_events)

      %{
        session_id: session_id,
        source_app: first_event.source_app,
        blocks: blocks,
        start_time: first_event.inserted_at,
        end_time: last_event.inserted_at,
        duration_sec: DateTime.diff(last_event.inserted_at, first_event.inserted_at, :second)
      }
    end)
    |> Enum.sort_by(& &1.start_time, {:desc, DateTime})
  end

  # Build timeline blocks from sorted session events.
  # Pairs PreToolUse with PostToolUse events by tool_use_id.
  defp build_timeline_blocks(events) do
    # Create lookup for PostToolUse events by tool_use_id
    post_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type in [:PostToolUse, :PostToolUseFailure] and e.tool_use_id
      end)
      |> Map.new(fn e -> {e.tool_use_id, e} end)

    # Find all PreToolUse events and match with Post events
    pre_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_use_id
      end)

    # Build blocks from paired events
    blocks =
      pre_events
      |> Enum.map(fn pre ->
        post = Map.get(post_events, pre.tool_use_id)

        %{
          tool_use_id: pre.tool_use_id,
          tool_name: pre.tool_name,
          start_time: pre.inserted_at,
          end_time: if(post, do: post.inserted_at, else: pre.inserted_at),
          duration_ms: if(post, do: post.duration_ms, else: nil),
          status: if(post, do: event_status(post), else: :pending),
          summary: event_summary(pre, post)
        }
      end)

    # Add idle gaps between blocks
    add_idle_gaps(blocks, events)
  end

  defp event_status(%{hook_event_type: :PostToolUse}), do: :success
  defp event_status(%{hook_event_type: :PostToolUseFailure}), do: :failure
  defp event_status(_), do: :unknown

  defp event_summary(pre, _post) do
    input = (pre.payload || %{})["tool_input"] || %{}

    case pre.tool_name do
      "Bash" -> truncate(input["command"] || "", 60)
      "Read" -> Path.basename(input["file_path"] || "")
      "Write" -> Path.basename(input["file_path"] || "")
      "Edit" -> Path.basename(input["file_path"] || "")
      "Grep" -> "grep: #{truncate(input["pattern"] || "", 30)}"
      "Glob" -> "glob: #{truncate(input["pattern"] || "", 30)}"
      "Task" -> truncate(input["description"] || "", 50)
      "WebSearch" -> truncate(input["query"] || "", 40)
      "SendMessage" -> "msg: #{input["recipient"] || "?"}"
      "TaskCreate" -> truncate(input["subject"] || "", 40)
      _ -> pre.tool_name || "?"
    end
  end

  defp truncate(str, max) when is_binary(str) and byte_size(str) > max do
    String.slice(str, 0, max) <> "..."
  end

  defp truncate(str, _max) when is_binary(str), do: str
  defp truncate(_, _), do: ""

  # Add idle gaps between tool blocks.
  defp add_idle_gaps(blocks, all_events) do
    sorted_blocks = Enum.sort_by(blocks, & &1.start_time, {:asc, DateTime})

    if Enum.empty?(sorted_blocks) do
      []
    else
      # Get session start/end times
      session_start = List.first(all_events).inserted_at
      session_end = List.last(all_events).inserted_at

      result = []

      # Add initial idle if needed
      first_block = List.first(sorted_blocks)

      result =
        if DateTime.compare(session_start, first_block.start_time) == :lt do
          [
            %{
              type: :idle,
              start_time: session_start,
              end_time: first_block.start_time
            }
            | result
          ]
        else
          result
        end

      # Add blocks and gaps between them
      result =
        sorted_blocks
        |> Enum.reduce(result, fn block, acc ->
          prev_end =
            if Enum.empty?(acc) do
              session_start
            else
              List.first(acc).end_time
            end

          # Add gap if there's time between previous and current
          acc =
            if DateTime.compare(prev_end, block.start_time) == :lt do
              [%{type: :idle, start_time: prev_end, end_time: block.start_time} | acc]
            else
              acc
            end

          # Add the block
          [Map.put(block, :type, :tool) | acc]
        end)

      # Add final idle if needed
      last_block = List.first(result)

      result =
        if last_block && DateTime.compare(last_block.end_time, session_end) == :lt do
          [
            %{
              type: :idle,
              start_time: last_block.end_time,
              end_time: session_end
            }
            | result
          ]
        else
          result
        end

      Enum.reverse(result)
    end
  end

  @doc """
  Calculate positioning for timeline blocks as percentages.
  """
  def calculate_block_positions(timeline_session, global_start, global_end) do
    total_duration = DateTime.diff(global_end, global_start, :millisecond)

    if total_duration == 0 do
      Enum.map(timeline_session.blocks, fn block ->
        Map.merge(block, %{left_pct: 0.0, width_pct: 0.0})
      end)
    else
      Enum.map(timeline_session.blocks, fn block ->
        start_offset = DateTime.diff(block.start_time, global_start, :millisecond)
        duration = DateTime.diff(block.end_time, block.start_time, :millisecond)

        left_pct = start_offset / total_duration * 100
        width_pct = max(duration / total_duration * 100, 0.5)

        Map.merge(block, %{
          left_pct: Float.round(left_pct, 2),
          width_pct: Float.round(width_pct, 2)
        })
      end)
    end
  end

  @doc """
  Get tool color class based on tool name.
  """
  def tool_color(tool_name) do
    case tool_name do
      "Bash" -> "bg-amber-500"
      "Read" -> "bg-blue-500"
      "Write" -> "bg-emerald-500"
      "Edit" -> "bg-violet-500"
      "Grep" -> "bg-cyan-500"
      "Glob" -> "bg-teal-500"
      "Task" -> "bg-indigo-500"
      "WebSearch" -> "bg-orange-500"
      "WebFetch" -> "bg-orange-400"
      "SendMessage" -> "bg-fuchsia-500"
      "TaskCreate" -> "bg-pink-500"
      "TaskUpdate" -> "bg-pink-400"
      "TeamCreate" -> "bg-cyan-600"
      _ -> "bg-zinc-500"
    end
  end

  @doc """
  Generate time axis labels for the timeline.
  """
  def time_axis_labels(start_time, end_time, count \\ 10) do
    total_sec = DateTime.diff(end_time, start_time, :second)

    if total_sec <= 0 do
      []
    else
      interval = max(div(total_sec, count), 1)

      0..count
      |> Enum.map(fn i ->
        offset_sec = i * interval
        label = format_time_offset(offset_sec)
        position_pct = Float.round(offset_sec / total_sec * 100, 2)

        %{label: label, position_pct: position_pct}
      end)
      |> Enum.take_while(fn %{position_pct: pos} -> pos <= 100 end)
    end
  end

  defp format_time_offset(0), do: "+0s"
  defp format_time_offset(sec) when sec < 60, do: "+#{sec}s"

  defp format_time_offset(sec) when sec < 3600 do
    mins = div(sec, 60)
    "+#{mins}m"
  end

  defp format_time_offset(sec) do
    hours = div(sec, 3600)
    mins = rem(div(sec, 60), 60)
    if mins > 0, do: "+#{hours}h#{mins}m", else: "+#{hours}h"
  end
end
