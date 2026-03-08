defmodule Observatory.Fleet.AgentHealth do
  @moduledoc """
  Agent health computation: failure rate, stuck detection, and loop detection.
  Pure functions operating on event lists -- no web-layer dependencies.
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

      stuck? = latest && DateTime.diff(now, latest.inserted_at, :second) > @stuck_threshold_sec
      loops = detect_tool_loops(sorted_events)
      failure_rate = calculate_failure_rate(member_events)

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

    recent_tools
    |> Enum.chunk_by(& &1)
    |> Enum.filter(fn chunk -> length(chunk) >= 3 end)
    |> Enum.map(fn chunk -> %{tool: hd(chunk), count: length(chunk)} end)
  end
end
