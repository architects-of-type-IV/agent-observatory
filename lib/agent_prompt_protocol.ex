defmodule AgentPromptProtocol do
  @moduledoc """
  The communication protocol blocks that go into a multi-agent prompt.

  Extracted from the ICHOR IV agent observatory, where four separate prompt
  builders assembled agent instructions. The reason this is a library and not a
  handful of heredocs is that they used to be heredocs — inlined, drifting, and
  subtly different from each other. When the roster format in one builder
  disagrees with the roster format in another, agents address each other with
  ids that do not resolve, and nothing reports an error. They just stop talking.

  So: one source of truth for the rules, the roster, the contact list, and the
  templating.

  ## The blocks

  | Function | Block | Answers |
  |---|---|---|
  | `critical_rules/1` | CRITICAL RULES | How do I communicate at all? |
  | `roster_block/2` | TEAM ROSTER | Who exists and what are their ids? |
  | `allowed_contacts/5` | ALLOWED CONTACTS | Who may I talk to, and who not? |
  | `announce_ready/1` | PHASE 0 | How do I prove I am alive? |

  ## Why the rules are so blunt

  `critical_rules/1` reads as repetitive shouting because the failure it
  prevents is specific and common: an agent narrates *"I would send a message
  to the lead asking for the task list"* instead of calling the tool. The prose
  looks like progress and produces nothing. Naming the failure mode explicitly
  — "If you find yourself typing 'I would send...' STOP" — is what stops it.

  Tool names are configurable, because rules that name a tool the agent does not
  have are worse than no rules at all. See `AgentPromptProtocol.Config`.

  ## Example

      agents = [%{id: 1, name: "lead", capability: "coordinator"}, %{id: 2, name: "builder"}]
      rules  = [%{from: 1, to: 2, policy: "allow"}]

      AgentPromptProtocol.critical_rules("mcp__team__")
      AgentPromptProtocol.roster_block("run-7", ["lead", "builder"])
      AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7",
        AgentPromptProtocol.extra_contacts_for(hd(agents)))
  """

  alias AgentPromptProtocol.Config

  @typedoc "An agent slot on the canvas: an integer id and a name."
  @type agent :: %{
          required(:id) => integer(),
          required(:name) => String.t(),
          optional(any) => any
        }

  @typedoc """
  A directed communication rule between two slots.

  `policy` is `"allow"` for a direct channel or `"route"` for an indirect one,
  in which case `:via` names the relay slot.
  """
  @type comm_rule :: %{
          required(:from) => integer(),
          required(:to) => integer(),
          required(:policy) => String.t(),
          optional(:via) => integer() | nil
        }

  @typedoc "A `{session_id, description}` pair for a non-agent target."
  @type contact :: {String.t(), String.t()}

  @doc """
  The CRITICAL RULES block.

  `tool_prefix` is prepended to the configured tool names, for hosts that
  namespace their tools (`"mcp__team__"` giving `mcp__team__send_message`).

      iex> AgentPromptProtocol.critical_rules("mcp__team__") =~ "mcp__team__send_message"
      true
  """
  @spec critical_rules(String.t()) :: String.t()
  def critical_rules(tool_prefix \\ "") do
    send_fn = tool_prefix <> Config.send_function()
    inbox_fn = tool_prefix <> Config.inbox_function()

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
  The TEAM ROSTER block from explicit `{name, session_id}` pairs.

  The canonical roster builder; `roster_block/2` derives its entries and calls
  through to here. The operator is appended automatically.
  """
  @spec roster_from_entries([{String.t(), String.t()}]) :: String.t()
  def roster_from_entries(entries) do
    send_fn = Config.send_function()
    inbox_fn = Config.inbox_function()

    ids = Enum.map_join(entries, "\n", fn {name, sid} -> "  - #{name}: #{sid}" end)

    """
    TEAM ROSTER (use these EXACT IDs with #{send_fn}/#{inbox_fn}):
    #{ids}
      - #{Config.operator_id()}: #{Config.operator_id()}
    """
    |> String.trim_trailing()
  end

  @doc """
  The TEAM ROSTER block for a session and its member names.

  Session ids follow `<session>-<name>`, which is the convention
  `allowed_contacts/5` also assumes.

      iex> AgentPromptProtocol.roster_block("run-7", ["lead"]) =~ "- lead: run-7-lead"
      true
  """
  @spec roster_block(String.t(), [String.t()]) :: String.t()
  def roster_block(session, names) do
    names
    |> Enum.map(&{&1, "#{session}-#{&1}"})
    |> roster_from_entries()
  end

  @doc """
  The PHASE 0 ANNOUNCE READY block.

  The agent sends one message to itself. It looks pointless and is not: it is a
  smoke test proving the agent can actually reach the messaging tools, and it
  fails at startup rather than in the middle of a run.
  """
  @spec announce_ready(String.t()) :: String.t()
  def announce_ready(session_id) do
    """
    ============================================================
    PHASE 0: ANNOUNCE READY (do this FIRST, before anything else)
    ============================================================

    Call #{Config.send_function()} ONCE to announce you are ready:

      from: "#{session_id}"
      to: "#{session_id}"
      content: "COORDINATOR READY"

    This self-message is a protocol smoke test. Your parent is the scheduler --
    it has already started you. No READY message needs to go upstream.
    """
    |> String.trim_trailing()
  end

  @doc """
  The ALLOWED CONTACTS block, derived from communication rules.

  Resolves slot ids to session ids and lists only what this agent may contact.
  Two policies:

    * `"allow"` — a direct channel; the target's own session id is listed
    * `"route"` — an indirect one; the **relay's** session id is listed, described
      as `"target (routed via relay)"`, because the relay is who the agent
      actually sends to

  Everyone else is named in an explicit "Do NOT message ... directly" line.
  Stating the negative matters: a roster that merely omits someone reads, to a
  model, as an oversight it can helpfully work around.

  ## Parameters

    * `slot_id` — the current agent's slot
    * `comm_rules` — see `t:comm_rule/0`
    * `agents` — see `t:agent/0`
    * `session` — session prefix, e.g. `"pipeline-abc123"`
    * `extra_contacts` — non-agent targets, from `extra_contacts_for/1`
  """
  @spec allowed_contacts(integer(), [comm_rule()], [agent()], String.t(), [contact()]) ::
          String.t()
  def allowed_contacts(slot_id, comm_rules, agents, session, extra_contacts \\ []) do
    names = Map.new(agents, &{&1.id, &1.name})
    outgoing = Enum.filter(comm_rules, &(&1.from == slot_id))

    direct =
      outgoing
      |> Enum.filter(&(&1.policy == "allow"))
      |> Enum.map(fn rule ->
        name = name_for(names, rule.to)
        {"#{session}-#{name}", name}
      end)

    # The relay is the send target, not the ultimate recipient — the agent needs
    # the relay's id in its hands, with the real destination named in prose.
    routed =
      outgoing
      |> Enum.filter(&(&1.policy == "route"))
      |> Enum.map(fn rule ->
        target = name_for(names, rule.to)
        via = name_for(names, Map.get(rule, :via))
        {"#{session}-#{via}", "#{target} (routed via #{via})"}
      end)

    contacts = direct ++ routed ++ extra_contacts
    reachable = MapSet.new(contacts, fn {sid, _} -> sid end)

    blocked =
      agents
      |> Enum.reject(&(&1.id == slot_id or MapSet.member?(reachable, "#{session}-#{&1.name}")))
      |> Enum.map(& &1.name)

    """
    ALLOWED CONTACTS (use #{Config.send_function()} to these session_ids ONLY):
    #{contact_lines(contacts)}#{deny_line(blocked)}
    """
    |> String.trim_trailing()
  end

  @doc """
  Non-agent contacts an agent gets from its capability.

  Coordinators reach the operator, because they are the ones producing
  deliverables a human should see; nobody else does, so intermediate chatter
  does not reach the dashboard.

      iex> AgentPromptProtocol.extra_contacts_for(%{capability: "coordinator"})
      [{"operator", "final deliverables to the dashboard"}]

      iex> AgentPromptProtocol.extra_contacts_for(%{capability: "builder"})
      []
  """
  @spec extra_contacts_for(map()) :: [contact()]
  def extra_contacts_for(%{capability: capability}) do
    if capability in Config.operator_capabilities() do
      [{Config.operator_id(), Config.operator_description()}]
    else
      []
    end
  end

  def extra_contacts_for(_), do: []

  @doc """
  Render `{{var}}` placeholders. Delegates to `AgentPromptProtocol.Template`.
  """
  @spec render_template(String.t(), map(), keyword()) :: String.t()
  defdelegate render_template(template, vars, opts \\ []),
    to: AgentPromptProtocol.Template,
    as: :render

  defp contact_lines([]), do: "(none -- you are isolated; do not message anyone)"

  defp contact_lines(contacts) do
    Enum.map_join(contacts, "\n", fn {sid, description} -> ~s(- "#{sid}" -- #{description}) end)
  end

  defp deny_line([]), do: ""
  defp deny_line(names), do: "\nDo NOT message #{Enum.join(names, ", ")} directly."

  # A rule may name a slot that no longer exists, or a route rule may arrive
  # with no :via at all. Neither should crash prompt assembly; a visible
  # "unknown-3" in the prompt is diagnosable, a KeyError mid-spawn is not.
  defp name_for(_names, nil), do: "unknown"
  defp name_for(names, id), do: Map.get(names, id, "unknown-#{id}")
end
