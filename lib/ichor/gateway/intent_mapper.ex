defmodule Ichor.Gateway.IntentMapper do
  @moduledoc false

  @doc """
  Maps a hook event to a human-readable intent string for DecisionLog.cognition.intent.

  Dispatch table: (hook_event_type, tool_name, payload) -> String.t()
  """
  @spec map_intent(atom(), String.t() | nil, map() | nil) :: String.t()
  def map_intent(hook_event_type, tool_name, payload)

  def map_intent(:PreToolUse, "TeamCreate", payload) do
    team = get_in(payload, ["tool_input", "team_name"]) || "unknown"
    "team_create:#{team}"
  end

  def map_intent(:PostToolUse, "TeamCreate", payload) do
    team = get_in(payload, ["tool_input", "team_name"]) || "unknown"
    "team_created:#{team}"
  end

  def map_intent(:PreToolUse, "TeamDelete", _payload), do: "team_delete"
  def map_intent(:PostToolUse, "TeamDelete", _payload), do: "team_deleted"

  def map_intent(:PreToolUse, "SendMessage", payload) do
    recipient = get_in(payload, ["tool_input", "recipient"]) || "all"
    msg_type = get_in(payload, ["tool_input", "type"]) || "message"
    "send_#{msg_type}:#{recipient}"
  end

  def map_intent(:PostToolUse, "SendMessage", payload) do
    recipient = get_in(payload, ["tool_input", "recipient"]) || "all"
    msg_type = get_in(payload, ["tool_input", "type"]) || "message"
    "sent_#{msg_type}:#{recipient}"
  end

  def map_intent(:PreToolUse, "Task", payload) do
    agent_type = get_in(payload, ["tool_input", "subagent_type"]) || "general"
    "spawn_agent:#{agent_type}"
  end

  def map_intent(:PostToolUse, "Task", payload) do
    agent_type = get_in(payload, ["tool_input", "subagent_type"]) || "general"
    "agent_spawned:#{agent_type}"
  end

  def map_intent(:PreToolUse, "TaskCreate", _payload), do: "task_create"
  def map_intent(:PostToolUse, "TaskCreate", _payload), do: "task_created"

  def map_intent(:PreToolUse, "TaskUpdate", payload) do
    case get_in(payload, ["tool_input", "status"]) do
      nil -> "task_update"
      status -> "task_update:#{status}"
    end
  end

  def map_intent(:PostToolUse, "TaskUpdate", payload) do
    case get_in(payload, ["tool_input", "status"]) do
      nil -> "task_updated"
      status -> "task_updated:#{status}"
    end
  end

  def map_intent(:PreToolUse, "TaskList", _payload), do: "task_list"
  def map_intent(:PreToolUse, "TaskGet", _payload), do: "task_get"
  def map_intent(:PreToolUse, "EnterWorktree", _payload), do: "enter_worktree"
  def map_intent(:PostToolUse, "EnterWorktree", _payload), do: "worktree_entered"
  def map_intent(:PreToolUse, "EnterPlanMode", _payload), do: "enter_plan_mode"
  def map_intent(:PreToolUse, "ExitPlanMode", _payload), do: "exit_plan_mode"
  def map_intent(:PreToolUse, tool, _payload), do: "tool_call:#{tool || "unknown"}"
  def map_intent(:PostToolUse, tool, _payload), do: "tool_result:#{tool || "unknown"}"
  def map_intent(:PostToolUseFailure, tool, _payload), do: "tool_failure:#{tool || "unknown"}"
  def map_intent(:UserPromptSubmit, _tool, _payload), do: "user_prompt"
  def map_intent(:SessionStart, _tool, _payload), do: "session_start"
  def map_intent(:SessionEnd, _tool, _payload), do: "session_end"
  def map_intent(:SubagentStart, _tool, _payload), do: "subagent_start"
  def map_intent(:SubagentStop, _tool, _payload), do: "subagent_stop"
  def map_intent(:PermissionRequest, _tool, _payload), do: "permission_request"
  def map_intent(:Notification, _tool, _payload), do: "notification"
  def map_intent(:Stop, _tool, _payload), do: "session_stop"
  def map_intent(:PreCompact, _tool, _payload), do: "pre_compact"
  def map_intent(other, _tool, _payload), do: to_string(other)
end
