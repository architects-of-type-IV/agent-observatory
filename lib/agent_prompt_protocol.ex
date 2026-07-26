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
  | `roster_block/3` | TEAM ROSTER | Who exists and what are their ids? |
  | `allowed_contacts/5` | ALLOWED CONTACTS | Who may I talk to, and who not? |
  | `announce_ready/2` | PHASE 0 | How do I prove I am alive? |

  ## Session ids are shared infrastructure

  `session_id/2` builds `<session><sep><name>`, and everything else derives from
  it: the roster, the contacts block, and — outside this library — whatever
  creates the actual tmux sessions or mailboxes the agents run in.

  That makes it the one function that must not be reimplemented anywhere. If
  session creation and prompt generation compute ids differently, agents address
  endpoints that do not exist, and the failure is silent. Use `roster_entries/2`
  to get the same `{name, session_id}` pairs the prompt will contain, and drive
  session creation from those.

  ## Why the rules are so blunt

  `critical_rules/1` reads as repetitive shouting because the failure it
  prevents is specific and common: an agent narrates *"I would send a message
  to the lead asking for the task list"* instead of calling the tool. The prose
  looks like progress and produces nothing. Naming the failure mode explicitly
  — "If you find yourself typing 'I would send...' STOP" — is what stops it.

  ## Tool naming

  Every block names the messaging tools, so every block takes the same optional
  `tool_prefix`. Set it once as config and forget it:

      config :agent_prompt_protocol, tool_prefix: "mcp__ichor__"

  A prompt whose blocks disagree about what the tool is called is worse than one
  with no rules at all, so the prefix is applied uniformly or not at all.

  ## Example

      agents = [%{id: 1, name: "lead", capability: "coordinator"}, %{id: 2, name: "builder"}]
      rules  = [%{from: 1, to: 2, policy: "allow"}]

      AgentPromptProtocol.critical_rules()
      AgentPromptProtocol.roster_block("run-7", ["lead", "builder"])
      AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7",
        extra_contacts: AgentPromptProtocol.extra_contacts_for(hd(agents)))
  """

  alias AgentPromptProtocol.Config

  @typedoc "An agent slot: an integer id and a name."
  @type agent :: %{
          required(:id) => integer(),
          required(:name) => String.t(),
          optional(any) => any
        }

  @typedoc """
  A directed communication rule between two slots.

  `policy` is one of:

    * `"allow"` — a direct channel
    * `"route"` — indirect, with `:via` naming the relay
    * `"deny"` — an explicit prohibition, which overrides any `"allow"`
  """
  @type comm_rule :: %{
          required(:from) => integer(),
          required(:to) => integer(),
          required(:policy) => String.t(),
          optional(:via) => integer() | nil
        }

  @typedoc "A `{session_id, description}` pair for a non-agent target."
  @type contact :: {String.t(), String.t()}

  # Session ids

  @doc """
  Build the session id for an agent within a run.

  The single definition of the convention. Everything that needs to name an
  agent — prompts, tmux session creation, mailbox routing — goes through here.

      iex> AgentPromptProtocol.session_id("review-abc123", "lead")
      "review-abc123-lead"
  """
  @spec session_id(String.t(), String.t()) :: String.t()
  def session_id(session, name), do: "#{session}#{Config.session_separator()}#{name}"

  @doc """
  The `{name, session_id}` pairs for a run, in the order given.

  The data behind `roster_block/3`. Drive session creation from this so the
  endpoints that exist are exactly the ones the prompt names.

      iex> AgentPromptProtocol.roster_entries("run-7", ["lead", "builder"])
      [{"lead", "run-7-lead"}, {"builder", "run-7-builder"}]
  """
  @spec roster_entries(String.t(), [String.t()]) :: [{String.t(), String.t()}]
  def roster_entries(session, names), do: Enum.map(names, &{&1, session_id(session, &1)})

  # Blocks

  @doc """
  The CRITICAL RULES block.

  `tool_prefix` defaults to `AgentPromptProtocol.Config.tool_prefix/0`.

      iex> AgentPromptProtocol.critical_rules("mcp__team__") =~ "mcp__team__send_message"
      true
  """
  @spec critical_rules(String.t() | nil) :: String.t()
  def critical_rules(tool_prefix \\ nil) do
    send_fn = send_fn(tool_prefix)
    inbox_fn = inbox_fn(tool_prefix)

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

  The canonical roster builder; `roster_block/3` derives its entries and calls
  through to here. The operator is appended automatically.
  """
  @spec roster_from_entries([{String.t(), String.t()}], String.t() | nil) :: String.t()
  def roster_from_entries(entries, tool_prefix \\ nil) do
    ids = Enum.map_join(entries, "\n", fn {name, sid} -> "  - #{name}: #{sid}" end)

    """
    TEAM ROSTER (use these EXACT IDs with #{send_fn(tool_prefix)}/#{inbox_fn(tool_prefix)}):
    #{ids}
      - #{Config.operator_id()}: #{Config.operator_id()}
    """
    |> String.trim_trailing()
  end

  @doc """
  The TEAM ROSTER block for a run and its member names.

      iex> AgentPromptProtocol.roster_block("run-7", ["lead"]) =~ "- lead: run-7-lead"
      true
  """
  @spec roster_block(String.t(), [String.t()], String.t() | nil) :: String.t()
  def roster_block(session, names, tool_prefix \\ nil) do
    session
    |> roster_entries(names)
    |> roster_from_entries(tool_prefix)
  end

  @doc """
  The PHASE 0 ANNOUNCE READY block.

  The agent sends one message to itself. It looks pointless and is not: it is a
  smoke test proving the agent can actually reach the messaging tools, and it
  fails at startup rather than in the middle of a run.
  """
  @spec announce_ready(String.t(), String.t() | nil) :: String.t()
  def announce_ready(agent_session_id, tool_prefix \\ nil) do
    """
    ============================================================
    PHASE 0: ANNOUNCE READY (do this FIRST, before anything else)
    ============================================================

    Call #{send_fn(tool_prefix)} ONCE to announce you are ready:

      from: "#{agent_session_id}"
      to: "#{agent_session_id}"
      content: "COORDINATOR READY"

    This self-message is a protocol smoke test. Your parent is the scheduler --
    it has already started you. No READY message needs to go upstream.
    """
    |> String.trim_trailing()
  end

  @doc """
  The ALLOWED CONTACTS block, derived from communication rules.

  ## Policies

    * `"allow"` — a direct channel; the target's own session id is listed
    * `"route"` — indirect; the **relay's** session id is listed, because the
      relay is who the agent actually sends to, with the real destination named
      in prose
    * `"deny"` — an explicit prohibition. Denial overrides any `"allow"` or
      `"route"` between the same pair, so an explicit rule is never defeated by
      the order rules happen to appear in.

  Anyone unreachable is named in a "Do NOT message ... directly" line. Stating
  the negative matters: a roster that merely omits someone reads, to a model, as
  an oversight it can helpfully work around.

  When a direct channel and a relayed one resolve to the same session id, they
  are merged into one line — two consecutive identical ids read as a duplicate
  and invite a model to collapse them itself.

  ## Options

    * `:extra_contacts` — non-agent targets, from `extra_contacts_for/1`
    * `:tool_prefix` — override the configured prefix
  """
  @spec allowed_contacts(integer(), [comm_rule()], [agent()], String.t(), keyword()) :: String.t()
  def allowed_contacts(slot_id, comm_rules, agents, session, opts \\ [])

  def allowed_contacts(slot_id, comm_rules, agents, session, opts) when is_list(opts) do
    extra_contacts = Keyword.get(opts, :extra_contacts, [])
    tool_prefix = Keyword.get(opts, :tool_prefix)

    names = Map.new(agents, &{&1.id, &1.name})
    outgoing = Enum.filter(comm_rules, &(&1.from == slot_id))

    # An explicit deny beats a permissive rule between the same pair, regardless
    # of which came first in the list.
    denied = for r <- outgoing, policy(r) == "deny", into: MapSet.new(), do: r.to
    permitted = Enum.reject(outgoing, &MapSet.member?(denied, &1.to))

    contacts =
      permitted
      |> Enum.flat_map(&contact_for(&1, names, session))
      |> merge_by_session_id()
      |> Kernel.++(extra_contacts)

    reachable = MapSet.new(contacts, fn {sid, _} -> sid end)

    blocked =
      agents
      |> Enum.reject(
        &(&1.id == slot_id or MapSet.member?(reachable, session_id(session, &1.name)))
      )
      |> Enum.map(& &1.name)

    """
    ALLOWED CONTACTS (use #{send_fn(tool_prefix)} to these session_ids ONLY):
    #{contact_lines(contacts)}#{deny_line(blocked)}
    """
    |> String.trim_trailing()
  end

  # Backwards-compatible: a bare list of extra contacts rather than opts.
  def allowed_contacts(slot_id, comm_rules, agents, session, extra_contacts) do
    allowed_contacts(slot_id, comm_rules, agents, session, extra_contacts: extra_contacts)
  end

  # Authorization

  @doc """
  Whether `from` may send to `to` under these rules.

  The same decision `allowed_contacts/5` renders as prose, exposed as a
  predicate so the messaging tool can enforce it. Rules describing who may talk
  to whom are access control; a prompt that merely *describes* access control is
  a suggestion, and an agent that forgets or reasons around the block gets
  through with nothing logged.

  Deciding both from one rule set is the point — the text and the gate cannot
  disagree, because there is only one of them.

      iex> rules = [%{from: 1, to: 2, policy: "allow"}]
      iex> AgentPromptProtocol.can_send?(1, 2, rules)
      true
      iex> AgentPromptProtocol.can_send?(2, 1, rules)
      false

  A `"route"` rule does **not** authorize the direct send it describes — the
  whole point of the indirection is that the sender reaches the relay, not the
  target:

      iex> rules = [%{from: 3, to: 1, policy: "route", via: 2}]
      iex> AgentPromptProtocol.can_send?(3, 1, rules)
      false
      iex> AgentPromptProtocol.can_send?(3, 2, rules)
      true
  """
  @spec can_send?(integer(), integer(), [comm_rule()]) :: boolean()
  def can_send?(from, to, comm_rules), do: authorize(from, to, comm_rules) == :ok

  @doc """
  Authorize a send, with a reason when it is refused.

  Returns `:ok`, or `{:error, reason}` where reason is:

    * `:denied` — an explicit `"deny"` rule
    * `:no_rule` — nothing permits it

  The two are worth distinguishing when logging: a `:denied` send is an agent
  ignoring an instruction it was given, while `:no_rule` is more often a team
  definition that forgot an edge.

      iex> AgentPromptProtocol.authorize(1, 2, [%{from: 1, to: 2, policy: "deny"}])
      {:error, :denied}

      iex> AgentPromptProtocol.authorize(1, 2, [])
      {:error, :no_rule}
  """
  @spec authorize(integer(), integer(), [comm_rule()]) :: :ok | {:error, :denied | :no_rule}
  def authorize(from, to, comm_rules) do
    outgoing = Enum.filter(comm_rules, &(&1.from == from and &1.to == to))

    cond do
      Enum.any?(outgoing, &(policy(&1) == "deny")) -> {:error, :denied}
      Enum.any?(outgoing, &(policy(&1) == "allow")) -> :ok
      relays_to?(comm_rules, from, to) -> :ok
      true -> {:error, :no_rule}
    end
  end

  @doc """
  Authorize a send addressed by session id rather than slot id.

  What a messaging tool actually has in hand: two session ids off the wire. It
  resolves them back to slots via the roster and applies the same rules, so the
  gate speaks the same language as the tool.

  Returns `{:error, :unknown_sender}` or `{:error, :unknown_recipient}` when an
  id does not belong to the team — which is itself worth logging, since it means
  an agent invented an address.
  """
  @spec authorize_session(String.t(), String.t(), [comm_rule()], [agent()], String.t()) ::
          :ok | {:error, :denied | :no_rule | :unknown_sender | :unknown_recipient}
  def authorize_session(from_session_id, to_session_id, comm_rules, agents, session) do
    with {:ok, from} <- slot_for_session(from_session_id, agents, session, :unknown_sender),
         {:ok, to} <- slot_for_session(to_session_id, agents, session, :unknown_recipient) do
      authorize(from, to, comm_rules)
    end
  end

  @doc """
  Every slot `from` may send to directly, including relays it must route through.

  The set behind the contacts block, as data. Useful for building a tool's
  allowlist up front rather than checking one send at a time.

      iex> rules = [%{from: 1, to: 2, policy: "allow"}, %{from: 1, to: 3, policy: "route", via: 2}]
      iex> AgentPromptProtocol.recipients(1, rules)
      [2]
  """
  @spec recipients(integer(), [comm_rule()]) :: [integer()]
  def recipients(from, comm_rules) do
    outgoing = Enum.filter(comm_rules, &(&1.from == from))
    denied = for r <- outgoing, policy(r) == "deny", into: MapSet.new(), do: r.to

    outgoing
    |> Enum.reject(&MapSet.member?(denied, &1.to))
    |> Enum.flat_map(fn rule ->
      case policy(rule) do
        "allow" -> [rule.to]
        "route" -> List.wrap(Map.get(rule, :via))
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(denied, &1))
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

  @doc "Render `{{var}}` placeholders. Delegates to `AgentPromptProtocol.Template`."
  @spec render_template(String.t(), map(), keyword()) :: String.t()
  defdelegate render_template(template, vars, opts \\ []),
    to: AgentPromptProtocol.Template,
    as: :render

  # Private

  defp contact_for(rule, names, session) do
    case policy(rule) do
      "allow" ->
        name = name_for(names, rule.to)
        [{session_id(session, name), name}]

      "route" ->
        target = name_for(names, rule.to)
        via = name_for(names, Map.get(rule, :via))
        [{session_id(session, via), "#{target} (routed via #{via})"}]

      _ ->
        []
    end
  end

  # Two rules can resolve to the same endpoint — a direct channel to the relay
  # plus a route through it. One line per id, descriptions joined.
  defp merge_by_session_id(contacts) do
    contacts
    |> Enum.reduce({[], %{}}, fn {sid, description}, {order, seen} ->
      case Map.get(seen, sid) do
        nil -> {[sid | order], Map.put(seen, sid, [description])}
        existing -> {order, Map.put(seen, sid, existing ++ [description])}
      end
    end)
    |> then(fn {order, seen} ->
      order
      |> Enum.reverse()
      |> Enum.map(&{&1, seen |> Map.fetch!(&1) |> Enum.join("; also relays to ")})
    end)
  end

  defp policy(rule), do: Map.get(rule, :policy) || "allow"

  # A route rule authorizes reaching the relay, not the destination.
  defp relays_to?(comm_rules, from, relay) do
    Enum.any?(comm_rules, fn rule ->
      rule.from == from and policy(rule) == "route" and Map.get(rule, :via) == relay
    end)
  end

  defp slot_for_session(sid, agents, session, error) do
    case Enum.find(agents, &(session_id(session, &1.name) == sid)) do
      nil -> {:error, error}
      agent -> {:ok, agent.id}
    end
  end

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

  defp send_fn(prefix), do: prefix(prefix) <> Config.send_function()
  defp inbox_fn(prefix), do: prefix(prefix) <> Config.inbox_function()

  defp prefix(nil), do: Config.tool_prefix()
  defp prefix(prefix) when is_binary(prefix), do: prefix
end
