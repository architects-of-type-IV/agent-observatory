defmodule Ichor.Fleet.AgentHealth do
  @moduledoc """
  Compatibility wrapper for fleet agent health analysis.
  """
  defdelegate compute_agent_health(member_events, now), to: Ichor.Fleet.Analysis.AgentHealth
  defdelegate calculate_failure_rate(events), to: Ichor.Fleet.Analysis.AgentHealth
end
