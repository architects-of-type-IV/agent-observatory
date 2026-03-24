defmodule Ichor.Workshop.PromptProtocol do
  @moduledoc """
  Shared agent communication protocol for all prompt builders.

  This module is the single source of truth for the communication rules,
  team roster format, template rendering, and contact resolution that every
  agent prompt uses. All prompt assembly paths (TeamSpec.build_from_state,
  Workshop.Spawn, PipelinePrompts, PlanningPrompts) delegate to these
  functions instead of inlining the text.
  """

  require Logger

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

  @doc """
  Returns the TEAM ROSTER block from a list of `{name, session_id}` entries.

  This is the canonical roster builder. Both `roster_block/2` and custom
  roster construction delegate here.
  """
  @spec roster_from_entries([{String.t(), String.t()}]) :: String.t()
  def roster_from_entries(entries) do
    ids = Enum.map_join(entries, "\n", fn {name, sid} -> "  - #{name}: #{sid}" end)

    """
    TEAM ROSTER (use these EXACT IDs with send_message/check_inbox):
    #{ids}
      - operator: operator
    """
    |> String.trim_trailing()
  end

  @doc "Returns the TEAM ROSTER block with session-name IDs for the given session and name list."
  @spec roster_block(String.t(), [String.t()]) :: String.t()
  def roster_block(session, names) do
    entries = Enum.map(names, fn name -> {name, "#{session}-#{name}"} end)
    roster_from_entries(entries)
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

  @doc """
  Returns the ALLOWED CONTACTS block derived from comm_rules data.

  Resolves agent slot IDs to session IDs and lists only the contacts this agent
  is permitted to send_message to. Handles "allow" (direct) and "route" (indirect
  via relay) policies. `extra_contacts` appends non-agent targets like "operator".

  ## Parameters

    - `slot_id` -- the integer slot ID of the current agent
    - `comm_rules` -- list of `%{from: integer(), to: integer(), policy: String.t()}`
    - `agents` -- list of `%{id: integer(), name: String.t()}`
    - `session` -- tmux session prefix (e.g. "workshop-alpha" or "pipeline-abc123")
    - `extra_contacts` -- list of `{session_id, description}` tuples for non-agent targets

  """
  @spec allowed_contacts(
          integer(),
          [map()],
          [map()],
          String.t(),
          [{String.t(), String.t()}]
        ) :: String.t()
  def allowed_contacts(slot_id, comm_rules, agents, session, extra_contacts \\ []) do
    agent_map = Map.new(agents, fn a -> {a.id, a.name} end)

    outgoing =
      Enum.filter(comm_rules, fn rule -> rule.from == slot_id end)

    allowed =
      outgoing
      |> Enum.filter(&(&1.policy == "allow"))
      |> Enum.map(fn rule ->
        name = Map.get(agent_map, rule.to, "unknown-#{rule.to}")
        {"#{session}-#{name}", name}
      end)

    routed =
      outgoing
      |> Enum.filter(&(&1.policy == "route"))
      |> Enum.map(fn rule ->
        target = Map.get(agent_map, rule.to, "unknown-#{rule.to}")
        via = Map.get(agent_map, rule.via, "unknown-#{rule.via}")
        {"#{session}-#{via}", "#{target} (routed via #{via})"}
      end)

    all_contacts = allowed ++ routed ++ extra_contacts

    lines =
      Enum.map_join(all_contacts, "\n", fn {session_id, description} ->
        "- \"#{session_id}\" -- #{description}"
      end)

    all_sids = MapSet.new(all_contacts, fn {sid, _} -> sid end)

    blocked_names =
      agents
      |> Enum.reject(fn a ->
        a.id == slot_id or MapSet.member?(all_sids, "#{session}-#{a.name}")
      end)
      |> Enum.map(& &1.name)

    deny_line =
      case blocked_names do
        [] -> ""
        names -> "\nDo NOT message #{Enum.join(names, ", ")} directly."
      end

    """
    ALLOWED CONTACTS (use send_message to these session_ids ONLY):
    #{lines}#{deny_line}
    """
    |> String.trim_trailing()
  end

  @doc """
  Returns extra contacts for an agent based on its capability.

  Coordinators get the "operator" contact for delivering final results.
  All other capabilities get no extra contacts.
  """
  @spec extra_contacts_for(map()) :: [{String.t(), String.t()}]
  def extra_contacts_for(%{capability: "coordinator"}),
    do: [{"operator", "final deliverables to the dashboard"}]

  def extra_contacts_for(_), do: []

  @doc """
  Renders `{{var}}` placeholders in a template string.

  Unknown vars are left as-is. Logs a warning if any placeholders remain
  after rendering, which indicates missing vars.
  """
  @spec render_template(String.t(), %{String.t() => String.t()}) :: String.t()
  def render_template("", _vars), do: ""

  def render_template(template, vars) when is_binary(template) and is_map(vars) do
    rendered =
      Regex.replace(~r/\{\{(\w+)\}\}/, template, fn _match, key ->
        Map.get(vars, key, "{{#{key}}}")
      end)

    unresolved =
      Regex.scan(~r/\{\{(\w+)\}\}/, rendered)
      |> Enum.map(fn [_, key] -> key end)
      |> Enum.uniq()

    if unresolved != [] do
      Logger.warning(
        "PromptProtocol.render_template: unresolved vars #{inspect(unresolved)} in rendered prompt"
      )
    end

    rendered
  end
end
