# ADR-024: Team Supervision Trees

> Status: PROPOSED | Date: 2026-03-08

## Context

Teams in ICHOR IV are currently data structures discovered from disk. `TeamWatcher` polls `~/.claude/teams/` every few seconds, reads JSON files, and builds a list of team maps. Teams have no process identity, no supervision relationship with their members, and no lifecycle guarantees.

When a team member crashes (tmux session dies), nothing happens automatically. The heartbeat sweep eventually marks the ETS entry as stale. There is no restart, no notification chain, no structural response.

The BEAM's supervision primitives -- `Supervisor`, `DynamicSupervisor`, process linking, and configurable restart strategies -- solve exactly this problem. A team is a supervisor. Its members are its children.

## Current State

| Concern | Mechanism | Problem |
|---------|-----------|---------|
| **Team discovery** | `TeamWatcher` polls `~/.claude/teams/*.json` | Disk-based; no process structure |
| **Member tracking** | Team JSON contains member session IDs | Passive list; no lifecycle link |
| **Failure handling** | Heartbeat sweep marks stale after TTL | No restart, no escalation, no structural response |
| **Team creation** | `claude team create` writes disk JSON | External to ICHOR; no Elixir-side lifecycle |
| **Team deletion** | Manual cleanup of disk files + ETS | Multi-step, error-prone |

## Decision

Each team becomes a `DynamicSupervisor` process. Team members (agent processes from ADR-023) are its supervised children. The team's restart strategy determines how member failures propagate.

### Team Supervisor (`Observatory.Fleet.TeamSupervisor`)

```elixir
defmodule Observatory.Fleet.TeamSupervisor do
  use DynamicSupervisor

  defstruct [
    :name,            # team name (e.g., "frontend-squad")
    :project,         # project path or key
    :strategy,        # restart strategy config
    :lead_id,         # agent_id of the team lead (if any)
    :metadata         # arbitrary k/v
  ]

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    DynamicSupervisor.start_link(__MODULE__, opts, name: via(name))
  end

  @impl true
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, :one_for_one)
    DynamicSupervisor.init(strategy: strategy, max_restarts: 3, max_seconds: 60)
  end

  # ── Public API ──

  def spawn_member(team_name, agent_opts) do
    agent_opts = Keyword.put(agent_opts, :team, team_name)
    DynamicSupervisor.start_child(via(team_name), {Observatory.Fleet.AgentProcess, agent_opts})
  end

  def terminate_member(team_name, agent_id) do
    case Registry.lookup(Observatory.Fleet.AgentRegistry, agent_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(via(team_name), pid)
      [] -> {:error, :not_found}
    end
  end

  def members(team_name) do
    DynamicSupervisor.which_children(via(team_name))
  end

  defp via(name), do: {:via, Registry, {Observatory.Fleet.TeamRegistry, name}}
end
```

### Fleet Supervisor (Root)

```elixir
defmodule Observatory.Fleet.Supervisor do
  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def create_team(opts) do
    DynamicSupervisor.start_child(__MODULE__, {Observatory.Fleet.TeamSupervisor, opts})
  end

  def disband_team(team_name) do
    case Registry.lookup(Observatory.Fleet.TeamRegistry, team_name) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
end
```

### Supervision Hierarchy

```
Observatory.Supervisor (one_for_one)
  |
  +-- Observatory.Fleet.Supervisor (DynamicSupervisor)
  |     |
  |     +-- TeamSupervisor "frontend-squad" (DynamicSupervisor, :one_for_one)
  |     |     +-- AgentProcess "fe-lead"
  |     |     +-- AgentProcess "fe-worker-1"
  |     |     +-- AgentProcess "fe-worker-2"
  |     |
  |     +-- TeamSupervisor "backend-squad" (DynamicSupervisor, :rest_for_one)
  |     |     +-- AgentProcess "be-coordinator"
  |     |     +-- AgentProcess "be-lead"
  |     |     +-- AgentProcess "be-worker-1"
  |     |
  |     +-- AgentProcess "standalone-scout"    # no team, direct child of Fleet.Supervisor
  |
  +-- Observatory.GatewaySupervisor (rest_for_one)
  +-- Observatory.MeshSupervisor (rest_for_one)
  +-- Observatory.MonitorSupervisor (one_for_one)
  +-- ObservatoryWeb.Endpoint
```

### Restart Strategies Per Team Type

| Team Pattern | Strategy | Rationale |
|-------------|----------|-----------|
| **Independent workers** | `:one_for_one` | Workers are independent; one failure doesn't affect others |
| **Pipeline / DAG** | `:rest_for_one` | Lead must stay alive; if lead crashes, restart all downstream workers |
| **Paired review** | `:one_for_all` | Both agents depend on shared state; restart both on any failure |

The strategy is configurable per team at creation time. Default is `:one_for_one`.

### Team Lifecycle

```
Architect creates team via dashboard
  -> Fleet.Supervisor.create_team(name: "frontend-squad", strategy: :one_for_one)
  -> TeamSupervisor starts, registers in TeamRegistry
  -> PubSub broadcast {:team_created, "frontend-squad"}

Architect adds member
  -> TeamSupervisor.spawn_member("frontend-squad", id: "fe-worker-1", backend: %{type: :tmux})
  -> AgentProcess starts under TeamSupervisor
  -> PubSub broadcast {:agent_spawned, "fe-worker-1", team: "frontend-squad"}

Agent crashes (tmux session dies, SSH drops)
  -> AgentProcess terminates
  -> DynamicSupervisor applies restart strategy
  -> If :one_for_one: only the crashed agent restarts
  -> If :rest_for_one: crashed agent + all agents started after it restart
  -> PubSub broadcast {:agent_restarted, "fe-worker-1"}
  -> If max_restarts exceeded: TeamSupervisor itself crashes
  -> Fleet.Supervisor restarts the team (or escalates to Architect)
```

### What Happens to TeamWatcher

`TeamWatcher` is eliminated. Its responsibilities move to:

- **Team discovery**: `Fleet.Supervisor` + `TeamRegistry` (process-based)
- **Member enumeration**: `DynamicSupervisor.which_children/1`
- **State persistence**: Optional. Teams can be re-created from a manifest file on app restart, or treated as ephemeral (created per-session by the Architect)

The `~/.claude/teams/` disk polling loop is removed entirely. If backward compatibility with `claude team create` CLI is needed, a file watcher (`FileSystem` library) can bridge disk changes into `Fleet.Supervisor.create_team/1` calls -- but the source of truth is the supervision tree, not the disk.

## Consequences

- **Automatic failure recovery.** Supervisor restart strategies replace manual sweep-and-mark.
- **Structural guarantees.** A team cannot exist without a process. Members cannot exist without a team (or as standalone under Fleet.Supervisor).
- **Eliminates TeamWatcher polling.** No more disk reads every N seconds.
- **Eliminates manual cleanup.** `disband_team/1` terminates the supervisor, which terminates all children. One call, complete cleanup.
- **Configurable resilience.** Different team topologies get different restart strategies.
- **Ash integration.** `Fleet.Team` resource reads from `Fleet.TeamRegistry` via preparation. Same `DataLayer.Simple` pattern, new data source.
- **Standalone agents.** Agents without a team are children of `Fleet.Supervisor` directly. They still get supervision and registry, just no team-level restart strategy.
