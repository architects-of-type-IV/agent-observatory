---
id: UC-0100
title: Start and supervise SwarmMonitor process
status: draft
parent_fr: FR-4.1
adrs: [ADR-007]
---

# UC-0100: Start and Supervise SwarmMonitor Process

## Intent
Ensure `Observatory.SwarmMonitor` is started as a supervised child of `Observatory.Application`, registered under its own module name, and recoverable from crashes without data loss to the dashboard LiveView.

## Primary Actor
`Observatory.Application` supervisor

## Supporting Actors
- `Observatory.SwarmMonitor` GenServer
- `Observatory.TeamWatcher` (must be started first)
- `ObservatoryWeb.DashboardLive` (retains previous state on transient crash)

## Preconditions
- `Observatory.Application` is starting its supervision tree.
- `Observatory.TeamWatcher` is already in the child list before `SwarmMonitor`.
- `Phoenix.PubSub` with name `Observatory.PubSub` is started before `SwarmMonitor`.

## Trigger
`Observatory.Application.start/2` is called by the BEAM on application boot.

## Main Success Flow
1. The supervisor starts `Observatory.SwarmMonitor` by calling `SwarmMonitor.start_link([])`.
2. `init/1` executes, registers the process under the name `Observatory.SwarmMonitor`, initialises state, and sends the first `:poll_tasks` message.
3. The process appears in the supervision tree after `TeamWatcher` and before `ProtocolTracker`.
4. `GenServer.call(Observatory.SwarmMonitor, :get_state)` returns the current state map.

## Alternate Flows

### A1: Application boots with no team configs on disk
Condition: No `~/.claude/teams/*/config.json` files exist at startup time.
Steps:
1. `init/1` completes with `watched_projects: %{}` and `active_project: nil`.
2. The process is registered and healthy; the first `:poll_tasks` cycle finds no projects.
3. The dashboard LiveView renders with an empty `:swarm_state` assign.

## Failure Flows

### F1: SwarmMonitor crashes after startup
Condition: An unhandled exception occurs inside `handle_info`.
Steps:
1. The supervisor detects the crash and restarts `SwarmMonitor` via `:one_for_one`.
2. During the restart window, `GenServer.call(Observatory.SwarmMonitor, :get_state)` returns `{:error, :noproc}` or raises a timeout.
3. `DashboardLive.handle_info/2` for `{:swarm_state, _}` is not triggered; the dashboard retains its previous `:swarm_state` assign unchanged.
Result: Dashboard shows stale but non-crashed state; SwarmMonitor resumes polling after restart.

## Gherkin Scenarios

### S1: Successful startup and registration
```gherkin
Scenario: SwarmMonitor starts and registers under its module name
  Given Observatory.Application is starting its supervision tree
  And Observatory.TeamWatcher is already started
  When the supervisor calls SwarmMonitor.start_link([])
  Then the process is registered under the name Observatory.SwarmMonitor
  And GenServer.call(Observatory.SwarmMonitor, :get_state) returns a map without error
```

### S2: Process order in supervision tree
```gherkin
Scenario: SwarmMonitor appears after TeamWatcher and before ProtocolTracker
  Given the supervisor children list is inspected via Supervisor.which_children/1
  When the child order is extracted
  Then Observatory.TeamWatcher appears before Observatory.SwarmMonitor
  And Observatory.SwarmMonitor appears before Observatory.ProtocolTracker
```

### S3: Crash recovery retains dashboard state
```gherkin
Scenario: Dashboard retains previous swarm state during SwarmMonitor restart
  Given the dashboard LiveView has a non-empty :swarm_state assign
  When Observatory.SwarmMonitor crashes and is restarted by the supervisor
  Then the dashboard :swarm_state assign is unchanged during the restart window
  And after SwarmMonitor restarts, the dashboard receives a fresh {:swarm_state, state} broadcast
```

## Acceptance Criteria
- [ ] `Supervisor.which_children(Observatory.Supervisor)` lists `Observatory.TeamWatcher` before `Observatory.SwarmMonitor` and `Observatory.SwarmMonitor` before `Observatory.ProtocolTracker` (S2).
- [ ] `GenServer.call(Observatory.SwarmMonitor, :get_state)` returns a map after application boot with no crash (S1).
- [ ] Killing `Observatory.SwarmMonitor` via `Process.exit/2` results in the process being restarted without bringing down the application (F1, S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Application start options (empty list by default)
**Outputs:** Registered GenServer process; initial state map
**State changes:** Process table gains `Observatory.SwarmMonitor` entry; ETS and PubSub subscriptions initialised

## Traceability
- Parent FR: [FR-4.1](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
