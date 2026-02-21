---
id: UC-0035
title: Resolve agent display name from team data with cwd fallback
status: draft
parent_fr: FR-2.11
adrs: [ADR-002]
---

# UC-0035: Resolve Agent Display Name from Team Data with cwd Fallback

## Intent
`build_agent_name_map/2` builds a `session_id -> display_name` map by merging cwd-derived names with team-provided names. Team names take precedence: the merge is `Map.merge(cwd_names, team_names)` so team entries overwrite cwd-derived entries for the same session ID. When neither source has a name, the `SessionGroup` component falls back to the first 8 characters of the session UUID.

## Primary Actor
System

## Supporting Actors
- `ObservatoryWeb.DashboardFeedHelpers.build_agent_name_map/2`
- `ObservatoryWeb.Components.Feed.SessionGroup` (consumer, calls `agent_display_name/1`)

## Preconditions
- A list of `:SessionStart` events is available (possibly empty).
- A teams list is available (possibly empty, possibly without entries for all sessions).

## Trigger
`build_agent_name_map/2` is called by `build_feed_groups/2` once per `build_feed_groups` call with the full teams list and all `:SessionStart` events.

## Main Success Flow
1. A `:SessionStart` event for session `"sid-1"` has `cwd = "/Users/xander/code/project"`.
2. cwd-derived name map: `%{"sid-1" => "project"}` (using `Path.basename/1`).
3. The teams list includes a member with `session_id: "sid-1"` and `name: "lead"`.
4. Team name map: `%{"sid-1" => "lead"}`.
5. `Map.merge(cwd_names, team_names)` produces `%{"sid-1" => "lead"}`.
6. The session group for `"sid-1"` resolves `agent_name: "lead"`.

## Alternate Flows

### A1: Session not in any team and has SessionStart with cwd
Condition: No team member entry for `"sid-2"`, but a `:SessionStart` event has `cwd = "/Users/xander/code/myrepo"`.
Steps:
1. cwd-derived name: `%{"sid-2" => "myrepo"}`.
2. No team entry overwrites it.
3. The session group has `agent_name: "myrepo"`.

### A2: Session not in any team and has no SessionStart event
Condition: No `:SessionStart` event and no team member entry for `"sid-3"`.
Steps:
1. No cwd-derived name is produced for `"sid-3"`.
2. No team entry exists.
3. `build_agent_name_map/2` has no key for `"sid-3"`.
4. The `SessionGroup` component calls `short_session("sid-3")`, returning the first 8 characters of the UUID.

### A3: Team indexes by both :session_id and :agent_id
Condition: A team member has both `session_id: "sid-4"` and `agent_id: "abc"` fields.
Steps:
1. The team name map is indexed by both `session_id` and `agent_id`.
2. Lookups by either key return the same name.

## Failure Flows

### F1: cwd field is nil on SessionStart event
Condition: A `:SessionStart` event has `cwd: nil`.
Steps:
1. `Path.basename(nil)` raises `FunctionClauseError`.
2. Prevention: cwd-derived name extraction MUST guard against nil cwd and skip nil values.
Result: If the guard is missing, the build crashes. Guard MUST be in place per FR-2.11 implementation.

## Gherkin Scenarios

### S1: Team name overwrites cwd-derived name for same session
```gherkin
Scenario: Team-provided name takes precedence over cwd basename
  Given a :SessionStart event for session_id "sid-1" with cwd "/path/to/project"
  And the teams list contains a member with session_id "sid-1" and name "lead"
  When build_agent_name_map/2 is called
  Then the name map entry for "sid-1" is "lead"
  And not "project"
```

### S2: Session with cwd but not in teams resolves to cwd basename
```gherkin
Scenario: No team entry for session falls back to cwd basename
  Given a :SessionStart event for session_id "sid-2" with cwd "/path/to/myrepo"
  And no team member has session_id "sid-2"
  When build_agent_name_map/2 is called
  Then the name map entry for "sid-2" is "myrepo"
```

### S3: Session with no SessionStart and not in teams falls back to UUID truncation
```gherkin
Scenario: No team and no SessionStart causes agent_name to use UUID truncation
  Given no :SessionStart event exists for session_id "abcdefgh-1234-5678-abcd-123456789012"
  And no team member has session_id "abcdefgh-1234-5678-abcd-123456789012"
  When the SessionGroup component renders for this session
  Then it displays "abcdefgh" (first 8 chars of session_id)
```

### S4: nil cwd on SessionStart is skipped without crash
```gherkin
Scenario: SessionStart with nil cwd is skipped in cwd name extraction
  Given a :SessionStart event for session_id "sid-5" with cwd nil
  When build_agent_name_map/2 is called
  Then no crash occurs
  And "sid-5" has no cwd-derived entry in the name map
```

## Acceptance Criteria
- [ ] `mix test test/observatory_web/dashboard_feed_helpers_test.exs` includes a test where a team name entry for `"sid-1"` overwrites a cwd-derived `"project"` name; asserts the result is `"lead"` (S1).
- [ ] A test with a `:SessionStart` cwd and no team entry asserts the name map returns the cwd basename (S2).
- [ ] A test where the `SessionGroup` component renders for a session with no name map entry asserts the display shows the first 8 chars of the UUID (S3).
- [ ] A test with a `:SessionStart` event having `cwd: nil` asserts `build_agent_name_map/2` does not crash (S4).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** List of `:SessionStart` events (for cwd extraction), teams list (for name override)
**Outputs:** `%{session_id => display_name}` map
**State changes:** None (pure computation)

## Traceability
- Parent FR: [FR-2.11](../frds/FRD-002-agent-block-feed.md)
- ADR: [ADR-002](../../decisions/ADR-002-agent-block-feed.md)
