# Tmux Agent Architecture

## Goal

Keep agent orchestration simple:

- One tmux server
- One tmux session per team
- One window per agent
- Create tmux structure first, then attach the agent process to that window

This document is intentionally a simplification brief, not a full-system narrative.
The goal is to drastically reduce code footprint and moving parts around agent orchestration.
If a piece of logic does not directly help create teams, create agent windows, register agents,
deliver messages, or clean them up, it should be questioned and likely removed.

This gives the operator a clean address for every agent:

- tmux session name
- tmux window name
- agent id

That is enough to send messages from the outside and to tell agents how to contact each other.

## Simplification Intent

The current architecture has accumulated too much machinery around a problem that should be small.

The intended direction is:

- fewer abstractions
- fewer process types involved in agent spawn and delivery
- fewer discovery paths
- fewer naming schemes
- less duplicated state between tmux, Registry, ETS, and supervisors

The system should be understandable in one sentence:

```text
A team is a tmux session, an agent is a tmux window plus one AgentProcess, and Registry maps the two.
```

If implementation choices move away from that sentence, they are probably adding unnecessary complexity.

## Core Model

Treat tmux as the visible workspace and BEAM as the control plane.

```text
tmux server
  -> session: team-alpha
       -> window: operator
       -> window: scout-1
       -> window: builder-1
       -> window: reviewer-1

BEAM
  -> AgentProcess "operator"  -> backend %{type: :tmux, target: "team-alpha:operator"}
  -> AgentProcess "scout-1"   -> backend %{type: :tmux, target: "team-alpha:scout-1"}
  -> AgentProcess "builder-1" -> backend %{type: :tmux, target: "team-alpha:builder-1"}
  -> AgentProcess "reviewer-1"-> backend %{type: :tmux, target: "team-alpha:reviewer-1"}
```

The important rule is:

1. Ensure the team's tmux session exists.
2. Ensure the target window exists.
3. Start the agent process with that tmux target in its backend metadata.

Not the other way around.

This ordering is important because it removes ambiguity:

- tmux is the concrete runtime location
- AgentProcess is the control wrapper for that location
- Registry is the lookup table for the relationship

That means the code does not need extra indirection to figure out where an agent lives.

## Boot Sequence

The full OTP tree does not need to be explained every time. For agent orchestration, only this order matters:

```text
1. Start PubSub, Repo, Registry, and supervisors
2. Ensure tmux server is available
3. Create a tmux session when a team is created
4. Start the operator window and operator agent inside that team session
5. System is ready to add more windows to that team session
```

Everything else is supporting infrastructure.

The point here is to avoid turning the boot sequence into architecture theater. Most of the full OTP tree is irrelevant to understanding agent orchestration.

## Spawn Flow

When the operator creates a new agent:

```text
1. Pick the team session
   Example: team-alpha

2. Pick the window name
   Example: scout-1

3. Create the window if it does not exist
   tmux new-window -t team-alpha -n scout-1

4. Write any instruction overlay or startup context

5. Start AgentProcess(id: "scout-1", backend: %{type: :tmux, target: "team-alpha:scout-1"})

6. Register the agent in Ichor.Registry

7. Agent is now reachable by both:
   - BEAM name: {:agent, "scout-1"}
   - tmux target: team-alpha:scout-1
```

This is the whole lifecycle. The system does not need separate tmux sessions per agent. It only needs one tmux session per team.

It also does not need a long chain of helper layers to get there. The desired code path should stay close to:

```text
ensure team session
-> ensure agent window
-> start AgentProcess
-> register metadata
```

## Discovery

There are only two things to discover:

- Which agents exist
- Which tmux window each agent owns

The Registry should answer both:

```text
{:agent, "scout-1"} -> pid + %{team: "team-alpha", tmux_target: "team-alpha:scout-1", role: :worker, ...}
```

That means:

- Operators can list all agents and their tmux addresses
- Agents can be told exactly how to contact peers
- External tooling can send directly to `team_session:window_name`

No extra discovery story is needed.

If discovery requires more than Registry metadata plus tmux inspection, the design is getting too large again.

## Messaging

Sending a message should follow one path:

```text
send("scout-1", message)
  -> lookup agent in Registry
  -> GenServer.cast(agent_pid, {:message, message})
  -> AgentProcess delivers to tmux target "team-alpha:scout-1"
```

If the process is gone but the window still exists, a direct tmux fallback is acceptable, but it should stay a fallback.

The normal path is:

- Registry lookup
- Agent process
- tmux delivery to one known window

The design goal is to keep messaging on this one path as much as possible.
Multiple overlapping delivery systems create maintenance cost without improving the core operator workflow.

## Team Structure

The team layout is now trivial:

```text
team-alpha session
  operator
  scout-1
  builder-1

team-beta session
  operator
  reviewer-1
  coordinator-1
```

Names should be stable and human-readable. That matters more than deep OTP narration because humans will use these names directly.

## Failure and Cleanup

Two cleanup cases matter:

### Agent process stops

- Remove the Registry entry
- Decide whether to keep or kill the tmux window

Recommended default:

- Keep the window for inspection if the stop was unexpected
- Kill the window if the stop was intentional

### Tmux window disappears

- Detect that the target `team-session:window_name` no longer exists
- Stop the matching agent process
- Remove the Registry entry

Again, the cleanup model is simple because the tmux address is simple.

That simplicity is deliberate. Cleanup logic should be small enough that a new engineer can trace it in one pass.

## Recommended Rule Set

If this architecture is implemented or documented elsewhere, keep these rules:

1. One team, one tmux session.
2. One agent, one tmux window.
3. Create the team session first, then the agent window, then the agent process.
4. Store the tmux target in Registry metadata.
5. Use stable human-readable window names.
6. Let messaging target `session:window`.

## What To Remove

To keep the code footprint low, prefer removing or collapsing any logic that introduces:

- separate tmux sessions per agent
- multiple competing agent identity systems
- multiple discovery systems for the same agent
- multiple normal-case message delivery paths
- state duplicated only to compensate for unclear naming
- helper modules whose only purpose is to translate between avoidably different models

In practical terms, the code should trend toward one obvious spawn path, one obvious lookup path, and one obvious delivery path.

## Short Version

The system does not need a complicated tmux model.

Use:

- one tmux session per team
- one window per agent
- one BEAM process per agent
- one Registry entry that maps agent id to team session and window

That is enough to spawn agents, list them, message them, and let them refer to each other clearly.

That is also enough to justify deleting a large amount of orchestration code that exists only because the runtime model was previously overcomplicated.
