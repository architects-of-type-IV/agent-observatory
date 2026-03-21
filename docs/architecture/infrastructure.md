# Infrastructure (Host Layer)
Related: [Index](INDEX.md) | [Supervision Tree](supervision-tree.md) | [Workshop Domain](workshop-domain.md) | [Signals Domain](signals-domain.md)

Infrastructure owns: runtime host layer -- supervisors, registry, tmux adapter, TeamLaunch execution, HITL relay.
Infrastructure does NOT own: business logic, domain rules. It is called by Workshop and Factory; it never calls into them.

---

## Role in the Architecture

Infrastructure is the imperative shell (AD-4). All side effects that touch the filesystem, shell, or external processes live here:
- Writing tmux scripts to disk
- Creating tmux sessions and windows via `System.cmd`
- Registering/deregistering agent processes in the Registry
- Delivering messages via tmux `send-keys`
- Pausing/unpausing Claude Code agents (HITLRelay)

Business logic belongs in Workshop and Factory. Infrastructure executes it.

---

## Core Modules

### Fleet.Runtime (target -- current: Infrastructure + Control.FleetSupervisor)

`DynamicSupervisor` owning all `AgentProcess` instances. The OTP root for all live agents.

**Key responsibilities**:
- Start AgentProcess under supervision when agents are launched
- Terminate AgentProcess when agents end or are disbanded
- List all active agents (delegated to Registry reads)
- Group agents into TeamSupervisor trees for team-level operations

After X1 fix: Fleet.Runtime subscribes to `:session_discovered` signal and creates AgentProcess. EventStream no longer calls into this module directly.

### Fleet.AgentProcess

GenServer per live agent. The BEAM-side representation of a running Claude agent.

**Holds**:
- Agent mailbox (pending messages not yet delivered)
- Backend reference (tmux session + window address)
- Agent status (active/idle/ended)
- Escalation state

**Receives**:
- `send_message/2` -- routes to backend (tmux or other channel)
- `update_status/2` -- agent status transitions
- `get_state/1` -- retrieve current state for Dashboard

**Does NOT hold**: Business state. Does not know about pipelines, tasks, or projects. Pure infrastructure.

### Fleet.Launcher (target -- current: AgentLaunch + TeamLaunch + Registration + Cleanup)

Executes a compiled TeamSpec:
1. `Scripts.write_all(spec)` -- write tmux startup scripts to disk
2. `Session.create_all(spec)` -- create tmux session + windows via `System.cmd`
3. `Registration.register_all(spec)` -- register each agent in `Ichor.Registry` and start AgentProcess under FleetSupervisor

Also handles teardown:
- `disband_team(team_name)` -- terminates all AgentProcess instances for the team
- `kill_session(session_name)` -- destroys the tmux session

### Transport.Tmux (target -- current: Infrastructure.Tmux)

All tmux operations. The only module that calls `System.cmd("tmux", ...)`.

**Key operations**:
- `create_session(name, options)` -- creates a new tmux session
- `create_window(session, window_name, command)` -- opens a window running a command
- `send_keys(target, text)` -- delivers text to a pane (message delivery)
- `capture_pane(target)` -- reads pane output (for watchdog scanning)
- `kill_session(name)` -- destroys a session

No business logic. All inputs are pre-validated by callers.

### Transport.HITL (target -- current: Infrastructure.HITLRelay)

Hold GenServer for Human-in-the-Loop pause/unpause state.

**Keep this GenServer**: holds pause state that multiple callers need to observe concurrently. Pausing one agent pauses its ability to receive new messages until the operator unpauses.

After X2 fix: HITLRelay is called by an Infrastructure subscriber reacting to `:escalation_level_2` signal. AgentWatchdog no longer calls it directly.

### Fleet.HostRegistry (target -- current: Control.HostRegistry)

Elixir `Registry` wrapper for agent process lookup by session ID. Used by the Bus for target resolution and by the Dashboard for live fleet display.

---

## Ash Resources in Infrastructure (temporary home)

Three Ash resources currently live in `Infrastructure` but should move (DB2 from audit):

| Resource | Target Domain | Reason |
|----------|--------------|--------|
| `CronJob` | Factory | Cron jobs are scheduled Factory work, not infrastructure concerns |
| `HITLInterventionEvent` | SignalBus | Audit records for signal-driven interventions |
| `WebhookDelivery` | Factory or Transport | Webhook delivery is durable retry work, close to Factory's webhook outbound concern |

Migration tracked as W5-5 (after W4-2 and W2-2 complete).

---

## TeamLaunch Execution Flow

```
Input: %Infrastructure.TeamSpec{agents: [...], session: name, scripts_dir: path}

1. Scripts.write_all(spec)
   - For each agent in spec: write startup script to scripts_dir
   - Script: `claude --permission-level X /path/to/project`

2. Session.create_all(spec)
   - tmux new-session -d -s {session_name}
   - For each agent: tmux new-window -t {session_name} -n {agent_name} {script}
   - Wait for windows to initialize (with timeout)

3. Registration.register_all(spec)
   - For each agent: Registry.register(Ichor.Registry, session_id, pid)
   - For each agent: FleetSupervisor.start_child(AgentProcess, agent_attrs)
   - Emit :team_spawned signal
```

All three steps are transactional in practice -- if any step fails, the cleanup path runs to undo partial work.

---

## CommPolicy (new from Workshop agent)

CommRule in the Workshop design maps to CommPolicy enforcement in Infrastructure.

When `policy: "via"` is set on a CommRule, the Bus routes messages through the relay agent instead of directly. The Bus checks CommPolicy before delivering:

```elixir
# Bus delivery with CommPolicy enforcement
def deliver(from_id, to_id, message) do
  case CommPolicy.check(from_id, to_id) do
    :allow -> deliver_direct(to_id, message)
    {:via, relay_id} -> deliver_direct(relay_id, forward(message, to_id))
    :deny -> {:error, :comm_denied}
  end
end
```

CommPolicy reads from the TeamSupervisor's stored CommRules (copied from Workshop design at launch time). This means comm rules are fixed for the lifetime of the team -- changes require relaunching.

---

## Operator.Inbox (planned abstraction)

Three modules currently write JSON to `~/.claude/inbox/` with different schemas:
- AgentWatchdog (crash notifications)
- TeamWatchdog (run completion notifications)
- Runner (HITL prompts)

**Target**: `Operator.Inbox.write(type, payload)` owns the directory, schema, and filename convention. Single write path. Consistent schema for the Operator agent to read.

This is a small module. Tracked as W1-1 (Wave 1, fully parallel).

---

## Non-Goals

Infrastructure explicitly does NOT:
- Make business decisions (which agent gets reassigned, which tasks to reset)
- Know about pipelines, projects, or team designs
- Hold Ash resources for business state
- Emit signals that contain business semantics (emits `:agent_process_started`, not `:run_began`)
- Call back into Workshop, Factory, or Signals
