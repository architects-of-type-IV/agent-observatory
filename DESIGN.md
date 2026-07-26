# How the pieces relate

Context recovered from the extraction session, written down because it is not
obvious from any single file and took several wrong turns to arrive at. This
describes the ICHOR IV model these libraries came out of.

## The Workshop is where processes are defined

Not agents — *processes*. A team definition is a whole multi-agent workflow:
who exists, who starts whom, who may talk to whom, under what supervision
strategy, with what phased instructions each role follows.

Building one agent is easy. The Workshop exists because coordinating five of
them without a shared definition is not.

## Presets are the target output, not the payload

`lib/ichor/workshop/presets.ex` calls itself "hardcoded mock data" and it is —
in the precise sense that the Workshop UI was never finished, so the definitions
it should be producing were hand-written instead. They are stand-ins for
artifacts the builder should emit.

That makes them **acceptance criteria**. A team builder is done when it can
express all five from code:

| Preset | Agents | Strategy | Notable |
|---|---|---|---|
| `pipeline` | 2 | `one_for_one` | bidirectional |
| `solo` | 1 | `one_for_one` | degenerate case |
| `research` | 4 | `one_for_all` | fan-out, workers → lead only |
| `review` | 4 | `rest_for_one` | the only one using `route` *and* `deny` |
| `mes` | 5 | `one_for_one` | coordinator + 4 |

If a builder can produce those five, it can produce the teams that matter. If it
can't, it is underspecified. `review` in particular is the whole policy
vocabulary in one definition, which is why it is a test case in this library.

The `strategy` field is the OTP supervision strategy, not decoration.
`rest_for_one` on the review chain means a restart cascades down the chain in
order; `one_for_all` on the research squad means the lead going down takes its
workers with it. Those are designed properties of each process.

`lib/ichor/factory/planning_prompts.ex` is the same concept authored the other
way — three modes × three agents, each prompt carrying numbered phases, explicit
wait/dispatch/collect steps, MCP tool scoping per role, and a tool budget. So:
presets author **composition and wiring**, planning_prompts authors **the phased
process per role**. Two halves of one idea.

## Roster vs comm_rules

They answer different questions and are often conflated:

- **Roster** — who exists, and the exact id to address each one by. Identity.
- **comm_rules** — who is permitted to send to whom. Authorization.

The roster is a directory; comm_rules are RBAC for the `send_message` MCP tool.

## Session ids are shared infrastructure

`<session><sep><name>` — built by `AgentPromptProtocol.session_id/2`.

The same string is three things at once:

1. the id an agent is told to address in its prompt,
2. the tmux window or mailbox actually created for it,
3. the key a message is routed on at send time.

Anything that computes it independently is a latent outage. If session creation
and prompt generation disagree, agents address endpoints that do not exist and
**nothing raises** — no error, no log, no failing test. The run just produces
nothing.

`roster_entries/2` exists so the launcher and the prompt builder consume one
list. Drive tmux window creation from it and the two cannot drift.

## RBAC needs an enforcement point

As of this extraction, in the original codebase, comm_rules were **advisory
only**. `Ichor.Signals.Operations.agent_send_message` takes
`from_session_id`, `to_session_id`, `content` and sends. `comm_rules` were read
in exactly two places — `workshop/spawn.ex`, to build the spec feeding prompt
generation, and `prompt_protocol.ex`, to render ALLOWED CONTACTS text.

Nothing consulted them at send time. The only thing between an agent and
messaging anyone was the prompt asking it not to.

`can_send?/3`, `authorize/3`, and `authorize_session/5` close that: the same
rule set now answers both "what does the prompt say?" and "is this send
allowed?". Wire `authorize_session/5` into the tool handler and the description
and the gate cannot disagree, because there is only one of them.

`{:error, :denied}` and `{:error, :no_rule}` are distinguished on purpose. A
denied send is an agent ignoring an instruction it was given — worth alerting
on. `:no_rule` is more often a team definition missing an edge.

## Why the prompt text is written the way it is

Each block prevents a specific observed failure:

- **CRITICAL RULES** — agents narrate *"I would send a message to the lead"*
  instead of calling the tool. The prose looks like progress and produces
  nothing. Naming the failure mode explicitly is what stops it.
- **ALLOWED CONTACTS deny line** — a roster that merely *omits* someone reads,
  to a model, as an oversight it can helpfully work around. Prohibition has to
  be stated.
- **Routed contacts list the relay** — the sender must address the relay, not
  the destination, or the indirection is decorative.
- **PHASE 0 announce-ready** — a self-message proving the agent can reach its
  tools at all, failing at startup rather than mid-run.

None of these are stylistic. Each is load-bearing.

## Related extractions

| Project | Role in this model |
|---|---|
| `agent_prompt_protocol` | Identity, authorization, and the prompt blocks |
| `tmux_channel` | Creates and addresses the endpoints named by the roster |
| `fleet_analysis` | Detects stuck/looping agents from the event log afterwards |

The seam between the first two is `roster_entries/2`.

## Still open

- **A headless team builder.** The `workshop_canvas` extraction took the
  editor's state transitions and left the definitions behind — the wrong cut,
  since without a UI the canvas half is the disposable half. What is wanted is a
  builder that emits team definitions, with the five presets as its test suite.
- **Where prompts live.** Presets carry personas; planning_prompts carries
  phased instructions per role. Whether a process definition owns its prompts
  decides whether the builder is one library or two.
- **`fleet_analysis.Topology`** produces graph nodes and edges for a renderer.
  With no frontend it is less useful than `Health` and `Sessions`, which are
  headless.
