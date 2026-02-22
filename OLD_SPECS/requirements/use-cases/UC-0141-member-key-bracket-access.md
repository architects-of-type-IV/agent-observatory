---
id: UC-0141
title: Access team member map keys using bracket syntax
status: draft
parent_fr: FR-5.17
adrs: [ADR-012]
---

# UC-0141: Access Team Member Map Keys Using Bracket Syntax

## Intent
Team member maps are plain maps (not structs), and their key schema varies by source: disk-sourced members use `:agent_id`, event-sourced members may use `:session_id`. Code that accesses member keys must use bracket syntax (`member[:agent_id]`) rather than dot syntax (`member.agent_id`) to avoid `KeyError` when a key is absent.

## Primary Actor
Developer

## Supporting Actors
- `DashboardTeamHelpers` functions (key access sites)
- Code review process
- `mix compile --warnings-as-errors` (does not catch this class of error; runtime only)

## Preconditions
- A code path accesses a field on a team member map.
- The member map may originate from disk (has `:agent_id`) or events (may have `:session_id` instead).

## Trigger
A developer writes code that accesses a team member field.

## Main Success Flow
1. Developer writes `member[:agent_id]` to access the agent ID.
2. If `:agent_id` is present, the value is returned.
3. If `:agent_id` is absent (e.g., event-sourced member), `nil` is returned safely.
4. No `KeyError` is raised.
5. `mix compile --warnings-as-errors` passes with zero warnings.

## Alternate Flows

### A1: Both :agent_id and :session_id may be needed
Condition: Code needs to locate a member by either key.
Steps:
1. `id = member[:agent_id] || member[:session_id]` safely extracts whichever key is present.
2. No crash if either is absent.

## Failure Flows

### F1: Dot syntax used on a map missing the key
Condition: `member.session_id` is used where the member was loaded from disk (has `:agent_id` but not `:session_id`).
Steps:
1. Elixir raises `KeyError: key :session_id not found in: %{agent_id: "abc123", ...}`.
2. The LiveView process crashes.
3. Developer replaces `member.session_id` with `member[:session_id]`.
4. Restarted LiveView process renders correctly; `member[:session_id]` returns `nil` for disk members.
Result: Runtime crash catches the dot-access bug; bracket access is the safe alternative.

## Gherkin Scenarios

### S1: Bracket access on disk member with absent key returns nil
```gherkin
Scenario: Accessing an absent key with bracket syntax returns nil without error
  Given a disk member map %{name: "worker-a", agent_id: "abc123"}
  When member[:session_id] is evaluated
  Then nil is returned
  And no KeyError is raised
```

### S2: Dot access on map missing the key raises KeyError
```gherkin
Scenario: Accessing an absent key with dot syntax raises KeyError
  Given a disk member map %{name: "worker-a", agent_id: "abc123"}
  When member.session_id is evaluated
  Then KeyError is raised with message "key :session_id not found"
```

### S3: find_agent_by_id uses bracket syntax to match safely
```gherkin
Scenario: find_agent_by_id handles members with different key schemas
  Given a list containing a disk member (agent_id present) and an event member (agent_id absent)
  When Enum.find/2 with &(&1[:agent_id] == target_id) is evaluated
  Then the disk member is found without error
  And the event member returns nil for [:agent_id] and is not matched
```

## Acceptance Criteria
- [ ] `grep -rn "\\.agent_id\|\\.session_id" lib/observatory_web/live/` returns no matches for direct dot access on member maps (S1, S2).
- [ ] All team member key accesses in `DashboardTeamHelpers` and `DashboardLive` use `member[:key]` bracket syntax (S1).
- [ ] A unit test confirms `member[:session_id]` returns `nil` for a disk-sourced map without that key (S1).
- [ ] `mix compile --warnings-as-errors` passes.

## Data
**Inputs:** Team member plain map (potentially from disk or events); key name atom
**Outputs:** Field value or `nil` (never a `KeyError`)
**State changes:** No state changes; read-only key access

## Traceability
- Parent FR: [FR-5.17](../frds/FRD-005-code-architecture-patterns.md)
- ADR: [ADR-012](../../decisions/ADR-012-dual-data-sources.md)
