defmodule Ichor.Events.Types.HookEventType do
  @moduledoc """
  Ash enum type for Claude hook event types.

  These correspond to the hook event names emitted by the Claude Code hook
  system and received by the Observatory gateway ingestor.
  """

  use Ash.Type.Enum,
    values: [
      :SessionStart,
      :SessionEnd,
      :UserPromptSubmit,
      :PreToolUse,
      :PostToolUse,
      :PostToolUseFailure,
      :PermissionRequest,
      :Notification,
      :SubagentStart,
      :SubagentStop,
      :Stop,
      :PreCompact,
      :TaskCompleted
    ]
end
