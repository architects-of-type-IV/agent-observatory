# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Vendor-Agnostic Fleet Control Architecture (2026-03-08)

### Vision Shift
Observatory is becoming **ICHOR IV** -- a sovereign control plane for autonomous agents. Not a monitoring dashboard, but a facility where agency is manufactured, distributed, monitored, and upgraded. Part of the Kardashev Type IV application suite.

Key concepts:
- **Architect** (user) has authority over everything
- **Archon** (coordinator Type IV) is ICHOR IV personified -- interprets Architect's will, drives fleet execution
- Agents arrive from anywhere (any vendor, any host, any protocol) and join the facility
- ICHOR observes, manages, controls, rearranges, and dictates

### Just Completed: ADR-001 Steps 1-4

**1. Channel Registry in Router** -- Runtime channel registration replaces hardcoded dispatch.
- `Channel` behaviour extended with `channel_key/0` and optional `skip?/1` callbacks
- Router reads `config :observatory, :channels` (list of `{module, opts}` tuples)
- Default: MailboxAdapter (primary), Tmux, WebhookAdapter
- New adapters just implement the behaviour and add to config -- no Router edits needed

**2. PaneMonitor GenServer** -- Makes hookless agents first-class citizens.
- Captures tmux pane output every 5s, parses `OBSERVATORY_DONE:`/`OBSERVATORY_BLOCKED:` signals
- Broadcasts on `"pane:signals"` PubSub topic, updates `AgentRegistry.touch/1`
- Supports both local Tmux and remote SshTmux capture

**3. Host + Tree Fields in AgentRegistry** -- Foundation for distributed agents and hierarchy.
- Added `host`, `parent_id`, `children`, `ssh_tmux` channel to agent entries

**4. SSH Tmux Channel Adapter** -- Remote agent management via SSH.
- `lib/observatory/gateway/channels/ssh_tmux.ex` -- full Channel behaviour implementation
- Address format: `"session@host"` (e.g., `"obs-builder@gpu-server-1"`)
- Uses `ssh -o BatchMode=yes -o ConnectTimeout=5` for passwordless auth
- Configurable via `config :observatory, SshTmux, socket_path: ..., ssh_opts: [...]`
- PaneMonitor captures from both local and remote tmux sessions
- Tested with live observatory-crew team -- message routing confirmed working

### Prior: Overstory-Inspired Features (still present)
- Cost Dashboard, Progressive Nudging, Agent Spawning, Quality Gates, Instruction Overlays
- See `SPECS/decisions/ADR-001-vendor-agnostic-fleet-control.md` for full gap analysis
- See `SPECS/decisions/ADR-002-ichor-iv-identity.md` for vision/naming

### Architecture Summary

| Layer | Before | After |
|-------|--------|-------|
| Transport | 3 hardcoded adapters in Router | Runtime channel registry via config |
| Agent observation | Claude hooks only | Hooks + PaneMonitor (tmux capture) |
| Agent identity | session_id only | session_id + host + parent_id + children |
| Naming | Observatory | ICHOR IV (codebase rename pending) |

### Remaining ADR-001 Steps
5. **Agent tree** -- spawn chain tracking, scoped authority, flexible hierarchy

### Open Issues
1. `ash_ai 0.5.0` SSE `{:error, :closed}` on MCP disconnect -- benign noise from upstream dep
2. Agent spawn UI -- no form yet, triggered via events only
3. Codebase rename from Observatory to ICHOR IV -- incremental, not yet started
