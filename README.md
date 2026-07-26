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
| `roster_block/2` | TEAM ROSTER | Who exists and what are their ids? |
| `allowed_contacts/5` | ALLOWED CONTACTS | Who may I talk to, and who not? |
| `announce_ready/1` | PHASE 0 | How do I prove I am alive? |

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
  %{from: 3, to: 1, policy: "route", via: 2}
]

AgentPromptProtocol.critical_rules("mcp__team__")
AgentPromptProtocol.roster_block("run-7", ["coordinator", "lead", "builder"])
AgentPromptProtocol.allowed_contacts(1, rules, agents, "run-7",
  AgentPromptProtocol.extra_contacts_for(hd(agents)))
AgentPromptProtocol.announce_ready("run-7-coordinator")
```

Session ids follow `<session>-<name>`. `roster_block/2` and `allowed_contacts/5`
agree on that convention, which is the whole point.

## Design notes

**The rules are blunt on purpose.** `critical_rules/1` reads as repetitive
shouting because the failure it prevents is specific: an agent narrates *"I
would send a message to the lead asking for the task list"* instead of calling
the tool. The prose looks like progress and produces nothing. Naming the failure
mode explicitly — "If you find yourself typing 'I would send...' STOP" — is what
stops it.

**Routed contacts list the relay, not the target.** With
`%{from: 3, to: 1, policy: "route", via: 2}`, agent 3 sees the *relay's* session
id, described as `coordinator (routed via lead)`. That's what it must actually
send to. Agent 1 stays in the deny line, so the indirection holds.

**Denial is stated, not implied.** Everyone unreachable is named in an explicit
"Do NOT message ... directly" line. A roster that merely omits someone reads, to
a model, as an oversight it can helpfully work around.

**Tool names are configurable**, because rules naming a tool the agent does not
have are worse than no rules at all.

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

68 tests and 16 doctests covering every block, both comm-rule policies, the
deny-line logic, template rendering and its missing-variable modes, and id
parsing. One test asserts the property the library exists for: that the ids in
the roster match the ids in the allowed-contacts block.

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
