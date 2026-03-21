defmodule Ichor.Workshop.PromptProtocol do
  @moduledoc """
  Shared agent communication protocol for all prompt builders.

  This module is the single source of truth for the communication rules,
  team roster format, and coordinator ready-announce block that every
  agent prompt must include. All prompt modules (TeamPrompts, PipelinePrompts,
  PlanningPrompts) delegate to these functions instead of inlining the text.

  ## Behaviour

  Implement `build_prompt/2` to produce a prompt string for a specific agent
  role given the agent map and a context map appropriate to that team type.
  """

  @doc "Returns the CRITICAL RULES block instructing the agent to use messaging tools only."
  @spec critical_rules(String.t()) :: String.t()
  def critical_rules(tool_prefix) do
    send_fn = "#{tool_prefix}send_message"
    inbox_fn = "#{tool_prefix}check_inbox"

    """
    CRITICAL RULES -- READ BEFORE DOING ANYTHING:
    - You communicate ONLY by calling #{send_fn} and #{inbox_fn} tools.
    - NEVER write text to describe what you would send. ALWAYS call the tool.
    - If you find yourself typing "I would send..." STOP. Call #{send_fn} instead.
    - Every message MUST go through #{send_fn}. No exceptions.
    - This is a pull-based inbox -- nothing arrives unless you call #{inbox_fn}.
    """
    |> String.trim_trailing()
  end

  @doc "Returns the TEAM ROSTER block with exact agent IDs for the given session and name list."
  @spec roster_block(String.t(), [String.t()]) :: String.t()
  def roster_block(session, names) do
    ids = Enum.map_join(names, "\n", fn name -> "  - #{name}: #{session}-#{name}" end)

    """
    TEAM ROSTER (use these EXACT IDs with send_message/check_inbox):
    #{ids}
      - operator: operator (for final deliverables to the dashboard)

    Your session ID is: #{session}-YOUR_NAME (see below)
    """
    |> String.trim_trailing()
  end

  @doc "Returns the PHASE 0 ANNOUNCE READY block for coordinator self-announcement."
  @spec announce_ready(String.t()) :: String.t()
  def announce_ready(session_id) do
    """
    ============================================================
    PHASE 0: ANNOUNCE READY (do this FIRST, before anything else)
    ============================================================

    Call send_message ONCE to announce you are ready:

      from: "#{session_id}"
      to: "#{session_id}"
      content: "COORDINATOR READY"

    This self-message is a protocol smoke test. Your parent is the scheduler --
    it has already started you. No READY message needs to go upstream.
    """
    |> String.trim_trailing()
  end

  @doc "Returns critical_rules/1, roster_block/2, and announce_ready/1 concatenated."
  @spec full_header(String.t(), [String.t()], String.t()) :: String.t()
  def full_header(session, names, tool_prefix) do
    """
    #{roster_block(session, names)}

    #{critical_rules(tool_prefix)}

    #{announce_ready("#{session}-coordinator")}
    """
    |> String.trim_trailing()
  end

  @callback build_prompt(agent :: map(), context :: map()) :: String.t()
end
