defmodule Ichor.Workshop.TeamPrompts do
  @moduledoc """
  Prompt builders for special-case agent prompts that are not yet
  driven by Workshop persona templates.

  MES role prompts (coordinator, lead, planner, researcher) have been
  migrated to persona templates in Workshop config / Presets. Only the
  corrective agent prompt remains here because it is spawned into an
  existing session with runtime-specific context (failure reason, attempt).
  """

  alias Ichor.Workshop.PromptProtocol

  @brief_format """
  TITLE: short descriptive name
  DESCRIPTION: one or two sentences
  PLUGIN: Elixir module name (e.g. Ichor.Plugins.Foo)
  SIGNAL_INTERFACE: which signals control it
  TOPIC: unique PubSub topic
  VERSION: 0.1.0
  FEATURES: comma-separated list
  USE_CASES: comma-separated list
  ARCHITECTURE: brief description of internal structure
  DEPENDENCIES: comma-separated Ichor modules required
  SIGNALS_EMITTED: comma-separated signal atoms
  SIGNALS_SUBSCRIBED: comma-separated signal atoms or categories
  """

  @spec corrective(String.t(), String.t(), String.t() | nil) :: String.t()
  def corrective(run_id, session, reason) do
    """
    You are a Corrective Agent for manufacturing run #{run_id}.
    Your session_id is: #{session}-corrective

    #{PromptProtocol.critical_rules("")}

    CONTEXT: The quality gate rejected the brief submitted by this run's coordinator.
    FAILURE REASON: #{reason || "unspecified -- check your inbox for details"}

    YOUR TASK (MAX 5 tool calls total):
    1. Call check_inbox with session_id "#{session}-corrective" for additional context.
    2. Synthesize a corrected plugin brief that addresses the failure reason.
    3. Call send_message to operator with the corrected brief in this EXACT format:

    #{String.trim(@brief_format)}

    No markdown. No headers. No extra text before TITLE.
    Also write the brief to plugins/briefs/#{run_id}.md (overwrite).

    After calling send_message, you are done. Stop.
    """
  end
end
