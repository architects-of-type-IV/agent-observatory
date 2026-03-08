# ADR-001: Vendor-Agnostic Fleet Control Architecture

> Status: PROPOSED | Date: 2026-03-08

## Context

Observatory is evolving from a Claude Code monitoring dashboard into a universal fleet control panel. The operator opens Observatory when starting work and uses it to manage, control, and launch their entire agent fleet -- regardless of vendor, location, or communication protocol.

## Current State

| Layer | Mechanism | Hardcoded? |
|-------|-----------|------------|
| **Transport** | 3 channel adapters behind a `Channel` behaviour (`deliver/2`, `available?/1`) | Router dispatches by compile-time aliases, not a registry |
| **Agent identity** | ETS registry, keyed by UUID or short name | No host/location field |
| **Liveness** | Tmux poll (5s) + hook events + TTL sweeps | Local tmux only |
| **Hierarchy** | `:standalone`, `:lead`, `:coordinator`, `:worker`, `:operator` | Flat enum, no tree structure |
| **Socket** | `~/.observatory/tmux/obs.sock` | Hardcoded in 2 places |

The `Channel` behaviour is the right abstraction -- `deliver/2` + `available?/1` is all a transport needs. But Router hard-wires which channels exist.

## Gaps Against Vision

**1. Remote tmux** -- No SSH channel. Today's tmux adapter calls `System.cmd("tmux", ...)` locally. For a remote agent you need `ssh host tmux -S /path ...` or an Observatory relay running on that host.

**2. Hookless agents** -- The only way an agent becomes visible today is via Claude hook POST or tmux poll. An agent without hooks and not in a tmux session is invisible. We need passive discovery (tmux pane monitoring for output signals) and/or active registration (agent calls an HTTP endpoint to announce itself).

**3. Distributed agents** -- AgentRegistry has no concept of host. An agent on a remote machine with the same tmux session name would collide. Need a `host` dimension in identity.

**4. Flexible hierarchy** -- The role enum is flat. No parent/child relationships. A master-coordinator who spawns coordinators who spawn leads is just... four agents with the same `:coordinator` role. No tree, no delegation chain, no scoped authority.

## Options

### Transport: Channel Registry (instead of compile-time wiring)

```
Router keeps a list of {module, priority} tuples.
On deliver: iterate channels in priority order, try each where available?/1 is true.
New channels register at runtime or config time -- no Router source edits.
```

This lets you add an SSH channel, a WebSocket channel, or a "remote Observatory relay" channel without touching Router. The Channel behaviour already defines the interface.

### Remote Agents: Three approaches

**A. SSH tunnel** -- Add an `SshTmux` channel adapter that wraps tmux commands in `ssh user@host`. Simple, works today with passwordless SSH. Downside: one SSH connection per deliver call, high latency.

**B. Observatory relay** -- Run a lightweight Observatory node on each remote host. The central Observatory talks to relays via WebSocket/HTTP. Each relay manages its local tmux sessions. The relay is itself just another channel adapter. This scales better but is more infrastructure.

**C. Hybrid** -- Start with SSH for 1-3 remote agents. Build the relay when you hit 10+.

### Hookless Agents: Pane Monitoring

Instead of waiting for hook POSTs, Observatory can `capture-pane` on a timer and parse output for signals:
- `OBSERVATORY_DONE: ...` -- agent signals completion
- `OBSERVATORY_BLOCKED: ...` -- agent needs help
- Last output timestamp -- detect staleness

This works for ANY agent in a tmux session regardless of vendor. The NudgeEscalator already watches for staleness -- it just needs a pane-capture data source instead of hook events.

### Hierarchy: Agent Tree with Delegation Chains

Replace the flat role enum with a tree structure:

```
%{
  id: "master-coord",
  role: :coordinator,
  parent_id: nil,           # root
  children: ["coord-a", "coord-b"],
  authority: [:spawn, :kill, :assign, :escalate],
  scope: %{teams: ["frontend", "backend"]}
}
```

Each agent knows its parent and children. Authority is explicit -- a coordinator can spawn leads but not other coordinators unless granted. Scope limits what teams/files/domains an agent can touch.

The current `AgentRegistry` entry gets a `parent_id` and `children` field. The hierarchy is emergent from the spawn chain -- when A spawns B, B's `parent_id = A.id`.

### Identity: Host-Qualified Agent IDs

Extend the registry key from `session_id` to `session_id@host`:

```
%{
  session_id: "obs-builder-0042",
  host: "macbook-local",        # or "gpu-server-1", "ci-runner"
  channels: %{
    tmux: %{session: "obs-builder-0042", host: "macbook-local", socket: "/path/to/sock"},
    mailbox: "obs-builder-0042",
    webhook: nil
  }
}
```

Local agents have `host: "local"`. Remote agents carry their host. Channel adapters use the host to decide local vs SSH vs relay dispatch.

## Decision: Implementation Order

Each step is independent and compiles clean on its own.

1. **Channel registry in Router** -- runtime registration, iterate on deliver. Small change, unlocks everything else.
2. **Pane monitor GenServer** -- `capture-pane` on heartbeat tick for all tmux agents, parse for signals. Makes hookless agents first-class.
3. **Host field in AgentRegistry** -- extend identity to include location.
4. **SSH tmux channel** -- `deliver/2` wraps commands in `ssh`. Gets you remote agents immediately.
5. **Agent tree** -- `parent_id`/`children` in registry, spawn chain tracking, scoped authority.

## Consequences

- Observatory becomes vendor-agnostic: any CLI agent that runs in tmux is a first-class citizen
- Remote agents are addressable without requiring them to run Observatory-specific code
- Hierarchy is emergent from spawn chains, not hardcoded role enums
- The Channel behaviour remains the core abstraction -- all extensibility flows through it
