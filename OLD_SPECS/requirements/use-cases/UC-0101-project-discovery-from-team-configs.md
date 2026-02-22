---
id: UC-0101
title: Discover project roots from team member cwd fields
status: draft
parent_fr: FR-4.2
adrs: [ADR-007]
---

# UC-0101: Discover Project Roots from Team Member cwd Fields

## Intent
On every poll cycle, SwarmMonitor reads all active and archived team `config.json` files, extracts each member's `cwd` field, and builds a `watched_projects` map keyed by the final directory component of each path. This map drives which `tasks.jsonl` files are subsequently polled.

## Primary Actor
`Observatory.SwarmMonitor`

## Supporting Actors
- File system (`~/.claude/teams/*/config.json`, `~/.claude/teams/.archive/*/config.json`)
- `tasks.jsonl` files at discovered project roots

## Preconditions
- The `~/.claude/teams/` directory exists (may be empty).
- SwarmMonitor is running and has received a `:poll_tasks` message.

## Trigger
`handle_info(:poll_tasks, state)` executes inside SwarmMonitor.

## Main Success Flow
1. SwarmMonitor reads all files matching `~/.claude/teams/*/config.json`.
2. SwarmMonitor reads all files matching `~/.claude/teams/.archive/*/config.json`.
3. For each config file, each member entry with a non-empty `cwd` field is extracted.
4. The project key is computed as `Path.basename(cwd)` (e.g., `"observatory"` from `"/Users/xander/code/www/kardashev/observatory"`).
5. Both sources are merged into `watched_projects` as `%{key => absolute_path}`.
6. Newly discovered projects are merged into the existing `watched_projects` map without evicting existing entries.
7. If `active_project` no longer exists in the merged map, it falls back to the first available key.
8. The active project's `tasks.jsonl` is read on the same cycle.

## Alternate Flows

### A1: Active project still present after re-discovery
Condition: The key stored in `state.active_project` exists in the newly merged `watched_projects`.
Steps:
1. The active project key is preserved unchanged.
2. Poll continues using the same `tasks.jsonl` path.

### A2: Archived team contributes a project not seen in active teams
Condition: A project path appears only in `.archive/*/config.json`.
Steps:
1. The project is merged into `watched_projects` with its key and path.
2. It is available for manual selection via `set_active_project/1`.

## Failure Flows

### F1: No config files found
Condition: `~/.claude/teams/` contains no subdirectories or all members lack a `cwd` field.
Steps:
1. `watched_projects` remains or becomes `%{}`.
2. `active_project` is set to `nil`.
3. All client API functions that require an active project return `{:error, :no_active_project}`.
Result: SwarmMonitor remains healthy and continues polling; dashboard shows empty project state.

### F2: config.json is malformed JSON
Condition: A config file cannot be decoded.
Steps:
1. `Jason.decode!/1` raises; the error is caught and the file is skipped.
2. Other valid config files are still processed.
Result: Partial discovery; the malformed config contributes no projects.

## Gherkin Scenarios

### S1: Project discovered from active team config
```gherkin
Scenario: SwarmMonitor discovers project root from team member cwd
  Given a file ~/.claude/teams/my-team/config.json exists
  And it contains a member with cwd "/Users/xander/code/my-project"
  When the :poll_tasks cycle executes
  Then watched_projects contains key "my-project" mapped to "/Users/xander/code/my-project"
  And tasks.jsonl is read from "/Users/xander/code/my-project/tasks.jsonl"
```

### S2: Active project falls back when its key disappears
```gherkin
Scenario: Active project falls back to first available when its key is no longer discovered
  Given state.active_project is "old-project"
  And the team config for "old-project" has been removed from disk
  When the :poll_tasks cycle re-discovers projects
  Then active_project is updated to the first key in the merged watched_projects map
```

### S3: No config files yield empty project map
```gherkin
Scenario: No discovered projects sets active_project to nil
  Given no ~/.claude/teams/*/config.json files exist
  When the :poll_tasks cycle executes
  Then watched_projects is an empty map
  And active_project is nil
  And get_state() returns a state map without error
```

## Acceptance Criteria
- [ ] After placing a `config.json` with a `cwd` field under `~/.claude/teams/test-team/`, `SwarmMonitor.get_state().watched_projects` contains the derived key within one poll cycle (3 seconds) (S1).
- [ ] Removing the config file and waiting one poll cycle does not evict projects already in `watched_projects`; the key persists (merge-only behaviour) (S1).
- [ ] With an empty `~/.claude/teams/` directory, `SwarmMonitor.get_state().active_project` is `nil` and `SwarmMonitor.set_active_project("missing")` returns `{:error, :unknown_project}` (S3).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** `~/.claude/teams/*/config.json` and `~/.claude/teams/.archive/*/config.json` file contents
**Outputs:** `watched_projects` map (`%{string => absolute_path_string}`); updated `active_project` key
**State changes:** `state.watched_projects` merged with new discoveries; `state.active_project` possibly updated

## Traceability
- Parent FR: [FR-4.2](../frds/FRD-004-swarm-monitor-protocol-tracker.md)
- ADR: [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md)
