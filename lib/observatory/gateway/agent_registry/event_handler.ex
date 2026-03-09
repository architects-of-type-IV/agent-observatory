defmodule Observatory.Gateway.AgentRegistry.EventHandler do
  @moduledoc """
  Transforms agent maps in response to hook events.

  Pure functions: takes an agent map and a hook event, returns an updated agent map.
  No ETS access, no side effects.
  """

  @doc "Apply a hook event to an existing agent map. Updates model, cwd, tool, status."
  @spec apply_event(map(), map()) :: map()
  def apply_event(agent, event) do
    agent
    |> maybe_put(:model, event.model_name)
    |> maybe_put(:cwd, event.cwd)
    |> update_current_tool(event)
    |> update_session_start(event)
    |> Map.put(:last_event_at, DateTime.utc_now())
    |> Map.put(:status, derive_status(event, agent))
  end

  # ── Tool Tracking ──────────────────────────────────────────────────

  defp update_current_tool(agent, %{hook_event_type: type, tool_name: tool})
       when type in [:PreToolUse, "PreToolUse"] and not is_nil(tool) do
    %{agent | current_tool: tool}
  end

  defp update_current_tool(agent, %{hook_event_type: type})
       when type in [:PostToolUse, :PostToolUseFailure, "PostToolUse", "PostToolUseFailure"] do
    %{agent | current_tool: nil}
  end

  defp update_current_tool(agent, _event), do: agent

  # ── Session Lifecycle ──────────────────────────────────────────────

  defp update_session_start(agent, %{hook_event_type: type})
       when type in [:SessionStart, "SessionStart"] do
    %{agent | started_at: DateTime.utc_now()}
  end

  defp update_session_start(agent, _event), do: agent

  defp derive_status(%{hook_event_type: type}, _existing)
       when type in [:SessionEnd, "SessionEnd"],
       do: :ended

  defp derive_status(_event, existing), do: existing.status

  # ── Helpers ────────────────────────────────────────────────────────

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
