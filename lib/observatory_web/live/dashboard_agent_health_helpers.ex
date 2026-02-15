defmodule ObservatoryWeb.DashboardAgentHealthHelpers do
  @moduledoc """
  Agent health monitoring helpers for the Observatory Dashboard.
  Computes health metrics including failure rate, stuck detection, and loop detection.
  """

  @stuck_threshold_sec 60
  @loop_detection_window 5

  @doc """
  Compute health status for an agent based on their events.
  Returns health level (:healthy, :warning, :critical) and issues list.
  """
  def compute_agent_health(member_events, now) do
    if Enum.empty?(member_events) do
      %{health: :unknown, issues: [], failure_rate: 0.0}
    else
      sorted_events = Enum.sort_by(member_events, & &1.inserted_at, {:desc, DateTime})
      latest = List.first(sorted_events)

      # Check if stuck (no events for >60s)
      stuck? = latest && DateTime.diff(now, latest.inserted_at, :second) > @stuck_threshold_sec

      # Check for tool loops (same tool used 3+ times consecutively)
      loops = detect_tool_loops(sorted_events)

      # Calculate failure rate
      failure_rate = calculate_failure_rate(member_events)

      # Determine health level
      issues = []
      issues = if stuck?, do: [{:stuck, latest} | issues], else: issues
      issues = if loops != [], do: [{:looping, loops} | issues], else: issues

      issues =
        if failure_rate > 0.5, do: [{:high_failure_rate, failure_rate} | issues], else: issues

      health =
        cond do
          stuck? or loops != [] -> :critical
          failure_rate > 0.3 -> :warning
          true -> :healthy
        end

      %{
        health: health,
        issues: issues,
        failure_rate: failure_rate,
        stuck?: stuck?,
        loops: loops
      }
    end
  end

  @doc """
  Calculate failure rate as ratio of failed tool uses to total tool uses.
  """
  def calculate_failure_rate(events) do
    tool_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type in [:PostToolUse, :PostToolUseFailure]
      end)

    if Enum.empty?(tool_events) do
      0.0
    else
      failures = Enum.count(tool_events, &(&1.hook_event_type == :PostToolUseFailure))
      Float.round(failures / length(tool_events), 2)
    end
  end

  defp detect_tool_loops(sorted_events) do
    recent_tools =
      sorted_events
      |> Enum.take(@loop_detection_window)
      |> Enum.filter(&(&1.hook_event_type == :PreToolUse))
      |> Enum.map(& &1.tool_name)

    # Find consecutive runs of 3+
    recent_tools
    |> Enum.chunk_by(& &1)
    |> Enum.filter(fn chunk -> length(chunk) >= 3 end)
    |> Enum.map(fn chunk -> %{tool: hd(chunk), count: length(chunk)} end)
  end

  @doc """
  Get health color class for health indicators.
  """
  def health_color(:healthy), do: "bg-emerald-500"
  def health_color(:warning), do: "bg-amber-500"
  def health_color(:critical), do: "bg-red-500"
  def health_color(_), do: "bg-zinc-600"

  @doc """
  Get health text color class.
  """
  def health_text_color(:healthy), do: "text-emerald-400"
  def health_text_color(:warning), do: "text-amber-400"
  def health_text_color(:critical), do: "text-red-400"
  def health_text_color(_), do: "text-zinc-500"

  @doc """
  Format health issue as human-readable string.
  """
  def format_issue({:stuck, latest_event}) do
    "Agent stuck - no activity for >60s (last event: #{relative_time_simple(latest_event.inserted_at)})"
  end

  def format_issue({:looping, loops}) do
    loop_desc =
      loops
      |> Enum.map(fn %{tool: tool, count: count} -> "#{tool} x#{count}" end)
      |> Enum.join(", ")

    "Possible loop detected: #{loop_desc}"
  end

  def format_issue({:high_failure_rate, rate}) do
    "High failure rate: #{Float.round(rate * 100, 0)}% of tools failing"
  end

  def format_issue(_), do: "Unknown issue"

  defp relative_time_simple(dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3600)}h ago"
    end
  end
end
