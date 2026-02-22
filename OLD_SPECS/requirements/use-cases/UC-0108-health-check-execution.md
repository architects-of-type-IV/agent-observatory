---
id: UC-0108
title: Execute external health check script and update health state
status: draft
parent_fr: FR-4.9
adrs: [ADR-007]
---

# UC-0108: Execute External Health Check Script and Update Health State

## Intent
On each health check cycle (every 30 seconds after an initial 5-second delay), SwarmMonitor invokes an external shell script, parses its JSON output, and updates the `health` map in state. The health map is then broadcast to the dashboard. If the script is absent or fails, the previous health state is retained without error.

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- `~/.claude/skills/swarm/scripts/health-check.sh` shell script
- `System.cmd/3` for process execution
- `Jason.decode/1` for output parsing

## Preconditions
- SwarmMonitor is running and `state.active_project` is non-nil.
- The `:health_check` message has fired.

## Trigger
`handle_info(:health_check, state)` executes and calls `do_health_check(state)`.

## Main Success Flow
1. SwarmMonitor checks that `@health_check_script` exists via `File.exists?/1`.
2. `System.cmd/3` is called with the script path, `[active_project_path, "10"]` as arguments.
3. The script exits with code 0 and returns JSON output.
4. `Jason.decode/1` parses the output into a map.
5. The `health` key in state is set to `%{healthy: bool, issues: [...], agents: map, timestamp: DateTime.utc_now()}`.
6. SwarmMonitor broadcasts the updated state on `"swarm:update"`.
7. The next `:health_check` is scheduled 30 seconds later.

## Alternate Flows

### A1: Script returns healthy with no issues
Condition: Script output is `{"healthy": true, "issues": {"details": []}, "agents": {}}`.
Steps:
1. `health.healthy` is set to `true`.
2. `health.issues` is `[]`.
3. The dashboard renders a green health indicator.

## Failure Flows

### F1: Script file does not exist
Condition: `File.exists?(@health_check_script)` returns `false`.
Steps:
1. `do_health_check/1` returns the unchanged state.
2. No crash or warning is logged.
3. The `:health_check` cycle continues on schedule.
Result: `state.health` retains its previous value (nil on first check if script was never present).

### F2: Script exits with non-zero status
Condition: `System.cmd/3` returns `{output, exit_code}` where `exit_code != 0`.
Steps:
1. The state is left unchanged.
2. No crash occurs; the next health check is still scheduled.
Result: `state.health` retains its previous value.

### F3: Script output is malformed JSON
Condition: `Jason.decode/1` returns `{:error, _}`.
Steps:
1. The state is left unchanged.
2. No crash occurs.
Result: `state.health` retains its previous value.

## Gherkin Scenarios

### S1: Successful health check updates health state
```gherkin
Scenario: Health check script succeeds and health state is updated
  Given the health check script exists at the expected path
  And the script exits 0 with valid JSON output including "healthy": true
  When :health_check fires
  Then state.health.healthy is true
  And state.health.timestamp is close to DateTime.utc_now()
  And a {:swarm_state, state} message is broadcast on "swarm:update"
```

### S2: Missing script leaves health state unchanged
```gherkin
Scenario: Absent health check script does not crash SwarmMonitor
  Given the health check script does not exist on disk
  When :health_check fires
  Then state.health is unchanged from its previous value
  And no error or crash occurs
  And the next :health_check message is scheduled
```

### S3: Non-zero exit code leaves health state unchanged
```gherkin
Scenario: Script failure preserves previous health state
  Given the health check script exits with code 1
  When :health_check fires
  Then state.health is unchanged from its previous value
  And SwarmMonitor continues running
```

## Acceptance Criteria
- [ ] With a mock health script that outputs valid JSON and exits 0, `SwarmMonitor.get_state().health.healthy` is a boolean within 40 seconds of startup (S1).
- [ ] With the script path pointing to a non-existent file, `SwarmMonitor.get_state().health` is `nil` after 40 seconds (initial value preserved), and no crash occurs (S2).
- [ ] With a mock script that exits 1, `SwarmMonitor.get_state().health` is unchanged (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Active project path; script path `~/.claude/skills/swarm/scripts/health-check.sh`; threshold argument `"10"`
**Outputs:** `state.health` map with `healthy`, `issues`, `agents`, `timestamp` keys
**State changes:** `state.health` updated on successful script execution; unchanged on failure

## Traceability
- Parent FR: [FR-4.9](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
