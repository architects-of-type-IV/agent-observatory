defmodule IchorWeb.DashboardTimelineHelpers do
  @moduledoc """
  Timeline computation helpers for the Ichor Dashboard.
  Converts events into timeline blocks for swimlane visualization.
  """

  alias Ichor.Activity.EventAnalysis

  @doc """
  Compute timeline data from events grouped by session.
  Delegates to Activity.EventAnalysis.timeline/1.
  """
  def compute_timeline_data(events), do: EventAnalysis.timeline(events)

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
  def tool_color("Bash"), do: "bg-brand"
  def tool_color("Read"), do: "bg-info"
  def tool_color("Write"), do: "bg-success"
  def tool_color("Edit"), do: "bg-violet"
  def tool_color("Grep"), do: "bg-cyan"
  def tool_color("Glob"), do: "bg-teal-500"
  def tool_color("Task"), do: "bg-interactive"
  def tool_color("WebSearch"), do: "bg-orange-500"
  def tool_color("WebFetch"), do: "bg-orange-400"
  def tool_color("SendMessage"), do: "bg-fuchsia-500"
  def tool_color("TaskCreate"), do: "bg-pink-500"
  def tool_color("TaskUpdate"), do: "bg-pink-400"
  def tool_color("TeamCreate"), do: "bg-cyan"
  def tool_color(_), do: "bg-low"

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
