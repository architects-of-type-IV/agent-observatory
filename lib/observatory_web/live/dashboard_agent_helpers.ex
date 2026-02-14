defmodule ObservatoryWeb.DashboardAgentHelpers do
  @moduledoc """
  Agent detail panel helpers for the Observatory Dashboard.
  Handles agent-specific data derivation and filtering.
  """

  @doc """
  Filter events to last N for a specific agent.
  """
  def agent_recent_events(events, agent_id, limit) do
    events
    |> Enum.filter(&(&1.session_id == agent_id))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  Filter tasks by owner matching agent_id.
  """
  def agent_tasks(active_tasks, agent_id) do
    Enum.filter(active_tasks, fn t ->
      t[:owner] == agent_id || match_agent_name?(t[:owner], agent_id)
    end)
  end

  defp match_agent_name?(owner, agent_id) when is_binary(owner) and is_binary(agent_id) do
    # Check if owner matches short form or full session_id
    owner == agent_id || String.starts_with?(agent_id, owner)
  end

  defp match_agent_name?(_owner, _agent_id), do: false
end
