defmodule Ichor.Control.Analysis.AgentHealth do
  @moduledoc """
  Agent health computation: failure rate, stuck detection, and loop detection.
  Pure functions operating on event lists.
  """

  @stuck_threshold_sec 60
  @loop_detection_window 5

  @doc """
  Compute health status for an agent based on their events.
  Returns health level (:healthy, :warning, :critical) and issues list.
  """
  @spec compute_agent_health(list(), DateTime.t()) :: map()
  def compute_agent_health([], _now) do
    %{health: :unknown, issues: [], failure_rate: 0.0}
  end

  def compute_agent_health(member_events, now) do
    sorted_events = Enum.sort_by(member_events, & &1.inserted_at, {:desc, DateTime})
    latest = List.first(sorted_events)

    stuck? = latest && DateTime.diff(now, latest.inserted_at, :second) > @stuck_threshold_sec
    loops = detect_tool_loops(sorted_events)
    failure_rate = calculate_failure_rate(member_events)

    issues = build_issues(stuck?, loops, failure_rate, latest)
    health = classify_health(stuck?, loops, failure_rate)

    %{health: health, issues: issues, failure_rate: failure_rate, stuck?: stuck?, loops: loops}
  end

  @doc """
  Calculate failure rate as ratio of failed tool uses to total tool uses.
  """
  @spec calculate_failure_rate(list()) :: float()
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

  defp build_issues(stuck?, loops, failure_rate, latest) do
    []
    |> then(fn issues -> if stuck?, do: [{:stuck, latest} | issues], else: issues end)
    |> then(fn issues -> if loops != [], do: [{:looping, loops} | issues], else: issues end)
    |> then(fn issues ->
      if failure_rate > 0.5, do: [{:high_failure_rate, failure_rate} | issues], else: issues
    end)
  end

  defp classify_health(stuck?, loops, _failure_rate) when stuck? == true or loops != [],
    do: :critical

  defp classify_health(_stuck?, _loops, failure_rate) when failure_rate > 0.3, do: :warning
  defp classify_health(_stuck?, _loops, _failure_rate), do: :healthy

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
