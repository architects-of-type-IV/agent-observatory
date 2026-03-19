defmodule IchorWeb.DashboardAgentHealthHelpers do
  @moduledoc """
  Presentation helpers for agent health indicators (colors, formatting).
  Domain logic lives in Ichor.Control.Analysis.AgentHealth.
  """

  defdelegate compute_agent_health(member_events, now), to: Ichor.Control.Analysis.AgentHealth
  defdelegate calculate_failure_rate(events), to: Ichor.Control.Analysis.AgentHealth

  def format_issue({:stuck, latest_event}) do
    "Agent stuck - no activity for >60s (last event: #{relative_time_simple(latest_event.inserted_at)})"
  end

  def format_issue({:looping, loops}) do
    loop_desc =
      Enum.map_join(loops, ", ", fn %{tool: tool, count: count} -> "#{tool} x#{count}" end)

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
