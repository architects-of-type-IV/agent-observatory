defmodule IchorWeb.DashboardTimelineHelpers do
  @moduledoc """
  Timeline computation helpers for the Ichor Dashboard.
  Converts events into timeline blocks for swimlane visualization.
  """

  @doc """
  Compute timeline data from events grouped by session.
  Delegates to Activity.EventAnalysis.timeline/1.
  """
  def compute_timeline_data(events), do: Ichor.Activity.EventAnalysis.timeline(events)

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
      "Bash" -> "bg-brand"
      "Read" -> "bg-info"
      "Write" -> "bg-success"
      "Edit" -> "bg-violet"
      "Grep" -> "bg-cyan"
      "Glob" -> "bg-teal-500"
      "Task" -> "bg-interactive"
      "WebSearch" -> "bg-orange-500"
      "WebFetch" -> "bg-orange-400"
      "SendMessage" -> "bg-fuchsia-500"
      "TaskCreate" -> "bg-pink-500"
      "TaskUpdate" -> "bg-pink-400"
      "TeamCreate" -> "bg-cyan"
      _ -> "bg-low"
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
