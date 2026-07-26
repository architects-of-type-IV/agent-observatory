# agent_prompt_protocol

The communication protocol blocks that go into a multi-agent prompt: rules,
roster, allowed contacts, and `{{var}}` templating.

Extracted from the ICHOR IV agent observatory. No dependencies.

## Why this is a library

In the original codebase four separate prompt builders assembled agent
instructions, and each one inlined its own heredocs. They drifted.

That failure is quiet in a way most are not. When the roster format in one
builder disagrees with the roster format in another, agents address each other
with ids that do not resolve — and nothing raises, nothing logs, no test goes
red. The agents simply stop talking to each other, and you find out from a run
that produced nothing.

So the value here is not the text. It's that there is exactly one copy of it.

## The blocks

| Function | Block | Answers |
|---|---|---|
| `critical_rules/1` | CRITICAL RULES | How do I communicate at all? |
| `roster_block/3` | TEAM ROSTER | Who exists and what are their ids? |
| `allowed_contacts/5` | ALLOWED CONTACTS | Who may I talk to, and who not? |
| `announce_ready/2` | PHASE 0 | How do I prove I am alive? |

Plus `session_id/2` and `roster_entries/2` (the data behind the roster) and
`can_send?/3` / `authorize_session/5` (the same rules as an enforcement point).

For how these pieces relate to the wider system they came from — team
definitions, supervision strategies, and where the prompt text's shape comes
from — see [DESIGN.md](DESIGN.md).

## Install

```elixir
def deps do
  [{:agent_prompt_protocol, path: "../agent_prompt_protocol"}]
end
```

## Use

```elixir
agents = [
  %{id: 1, name: "coordinator", capability: "coordinator"},
  %{id: 2, name: "lead",        capability: "lead"},
  %{id: 3, name: "builder",     capability: "builder"}
]

rules = [
  %{from: 1, to: 2, policy: "allow"},
  %{from: 3, to: 1, policy: "route", via: 2},
  %{from: 3, to: 2, policy: "deny"}
]

AgentPromptProtocol.critical_rules()
AgentPromptProtocol.roster_block("run-7", ["coordinator", "lead", "builder"])
AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7",
  extra_contacts: AgentPromptProtocol.extra_contacts_for(hd(agents)))
AgentPromptProtocol.announce_ready("run-7-coordinator")
```

## Session ids are shared infrastructure

`session_id/2` builds `<session><sep><name>`, and everything else derives from
it — the roster, the contacts block, and, outside this library, whatever creates
the tmux sessions or mailboxes the agents actually run in.

That makes it the one function that must not be reimplemented anywhere. If
session creation and prompt generation compute ids differently, agents address
endpoints that do not exist, and nothing raises. Drive session creation from
`roster_entries/2` and the two cannot drift:

```elixir
entries = AgentPromptProtocol.roster_entries("review-abc123", ["lead", "builder"])
#=> [{"lead", "review-abc123-lead"}, {"builder", "review-abc123-builder"}]

# the same ids the prompt will name
for {name, session_id} <- entries do
  TmuxChannel.Launcher.create_window("review-abc123", name, cwd, launch_cmd)
  # ... and session_id is what agents address
end

AgentPromptProtocol.roster_from_entries(entries)
```

## Roster vs comm_rules

They answer different questions and are easy to conflate:

- **Roster** — who exists, and the exact id to address each by. Identity.
- **comm_rules** — who is permitted to send to whom. Authorization.

The roster is a directory; comm_rules are RBAC for the `send_message` tool.

## Authorization

`allowed_contacts/5` renders the rules as prose for the agent to read. That is a
description, not a control: an agent that forgets or reasons around the block
gets through, and nothing logs it. The same decision is available as a
predicate, so the tool can enforce what the prompt describes:

```elixir
AgentPromptProtocol.can_send?(1, 2, rules)          #=> true
AgentPromptProtocol.authorize(4, 1, rules)          #=> {:error, :denied}
AgentPromptProtocol.authorize(1, 9, rules)          #=> {:error, :no_rule}
AgentPromptProtocol.recipients(1, rules)            #=> [2, 4]
```

In a tool handler, which has session ids rather than slot ids:

```elixir
case AgentPromptProtocol.authorize_session(from_sid, to_sid, rules, agents, session) do
  :ok -> deliver(from_sid, to_sid, content)
  {:error, reason} -> {:error, reason}
end
```

Deciding both from one rule set is the point — the text and the gate cannot
disagree, because there is only one of them. A test asserts exactly that: for
every agent, being listed in the contacts block matches `can_send?/3`.

`:denied` and `:no_rule` are distinguished deliberately. A denied send is an
agent ignoring an instruction it was given, which is worth alerting on;
`:no_rule` is more often a team definition missing an edge. `authorize_session/5`
also reports `:unknown_sender` / `:unknown_recipient`, which means an agent
invented an address.

A `"route"` rule authorizes reaching the **relay**, not the destination — the
whole point of the indirection.

## Design notes

**The rules are blunt on purpose.** `critical_rules/1` reads as repetitive
shouting because the failure it prevents is specific: an agent narrates *"I
would send a message to the lead asking for the task list"* instead of calling
the tool. The prose looks like progress and produces nothing. Naming the failure
mode explicitly — "If you find yourself typing 'I would send...' STOP" — is what
stops it.

**Three policies.** `"allow"` is a direct channel. `"route"` is indirect — the
sender sees the *relay's* session id, described as `lead (routed via reviewer)`,
because that is what it must actually send to, and the real destination stays in
the deny line so the indirection holds. `"deny"` is an explicit prohibition, and
it overrides any `"allow"` or `"route"` between the same pair regardless of the
order rules appear in.

**Contacts resolving to the same id share a line.** A direct channel to a relay
plus a route through it both address the relay. Two consecutive identical ids
read as a duplicate and invite a model to collapse them, so they are merged:
`- "review-1-reviewer" -- reviewer; also relays to lead (routed via reviewer)`.

**Denial is stated, not implied.** Everyone unreachable is named in an explicit
"Do NOT message ... directly" line. A roster that merely omits someone reads, to
a model, as an oversight it can helpfully work around.

**Tool names are configurable**, because rules naming a tool the agent does not
have are worse than no rules at all — and the prefix is applied to *every* block,
because a prompt whose blocks disagree about the tool's name has the same
problem.

## Templating

`AgentPromptProtocol.Template` does `{{var}}` substitution and nothing else — no
conditionals, no loops, no partials. A template needing control flow is a sign
the logic belongs in the code that assembles it, where it can be tested.

```elixir
Template.render("Hello {{name}}", %{"name" => "Ada"})       #=> "Hello Ada"
Template.variables("{{a}} {{b}} {{a}}")                     #=> ["a", "b"]
Template.unresolved("{{a}} {{b}}", %{"a" => 1})             #=> ["b"]
```

Missing variables are kept as `{{var}}` and warned about, by default. That is
deliberate: a prompt that visibly contains `{{run_id}}` is diagnosable from the
agent's transcript, whereas one that silently dropped the value looks fine and
behaves strangely. Override with `on_missing: :empty | :raise | :keep_quiet`, or
validate up front with `unresolved/2` before spawning.

## Agent ids

`AgentPromptProtocol.AgentId` parses structured session ids —
`<kind>-<run_id>-<role>` — so `"pipeline-abc123-builder"` becomes a struct
instead of a string split at every call site.

```elixir
{:ok, id} = AgentId.parse("pipeline-abc123-builder")
{id.kind, id.run_id, id.role}    #=> {:pipeline, "abc123", "builder"}
AgentId.run_id("mes-r1-lead")    #=> {:ok, "r1"}
AgentId.valid?("nonsense")       #=> false
```

## Configuration

Everything has a default; none of this is required.

```elixir
config :agent_prompt_protocol,
  send_function: "send_message",
  inbox_function: "check_inbox",
  tool_prefix: "",
  session_separator: "-",
  operator_id: "operator",
  operator_description: "final deliverables to the dashboard",
  operator_capabilities: ["coordinator"],
  id_kinds: [:mes, :pipeline, :planning]
```

`operator_capabilities` controls who gets the operator contact. Coordinators
only, by default — they produce the deliverables a human should see, so
intermediate chatter never reaches the dashboard.

## Tests

```
mix test
```

111 tests and 23 doctests covering every block, all three comm-rule policies and
their precedence, authorization by slot and by session id, contact merging, the
deny-line logic, template rendering and its missing-variable modes, and id
parsing.

Three assert the properties the library exists for: that the ids in the roster
match the ids in the allowed-contacts block, that a configured tool prefix
reaches every mention of the tool in every block, and that the authorization
gate agrees with the prose it renders for every agent.

One test renders the review-chain team's wiring verbatim — it is the only
team definition that uses all three policies at once.

## Changes from the original

- Namespace `Ichor.Workshop.PromptProtocol` → `AgentPromptProtocol`, with
  `AgentId` alongside and templating split into `AgentPromptProtocol.Template`.
- Tool names, operator identity, and id kinds moved from hardcoded strings to
  configuration.

Fixed along the way:

- **A route rule without `:via` crashed prompt assembly.** `rule.via` on a map
  lacking the key raises `KeyError`, and a `"route"` rule built by hand or
  loaded from older data may not have one. It now renders a visible `unknown`
  instead — a diagnosable prompt beats an exception mid-spawn.
- **An isolated agent got an empty contacts block.** With no matching rules the
  block listed nothing under "ALLOWED CONTACTS", which reads as an omission. It
  now says so explicitly: "(none -- you are isolated; do not message anyone)".
- **`AgentId.parse/1` used `String.to_existing_atom/1`**, so whether a valid id
  parsed depended on whether some unrelated module had already created the atom.
  Kinds are now compared as strings against the configured list.
- `AgentId.parse/1` no longer raises on a non-binary input, and `valid?/1` is
  new.
- **`"deny"` was silently ignored.** Only `"allow"` and `"route"` were matched,
  so a `deny` rule fell through both filters. The rendered output happened to be
  right — denial there is by omission — but nothing stated the intent, nothing
  tested it, and an `allow` alongside a `deny` would have won. Deny is now
  explicit and takes precedence.
- **The tool prefix reached only `critical_rules/1`.** One prompt could say
  `mcp__ichor__send_message` in its rules and `send_message` in its roster two
  paragraphs later — exactly the drift this library exists to prevent. It is now
  configuration, applied uniformly.
- **Two contacts resolving to the same session id printed as two lines.**

Added:

- `session_id/2` and `roster_entries/2`, exposing the id convention as data so
  session creation and prompt generation cannot diverge.
- `can_send?/3`, `authorize/3`, `authorize_session/5`, and `recipients/2`. In
  the original, comm_rules were advisory only — nothing consulted them at send
  time, so the prompt was the sole barrier. The same rules now serve as an
  enforcement point.
