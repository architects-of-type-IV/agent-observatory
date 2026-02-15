# Stage 3: Execution Plan

## Task 1: Fix handle_send_targeted_message return pattern
**FILES**:
- lib/observatory_web/live/dashboard_team_inspector_handlers.ex
- lib/observatory_web/live/dashboard_live.ex

**CHANGES**:
- dashboard_team_inspector_handlers.ex:60-77 -- Refactor to return socket (not {:noreply, socket}). Use push_event but return the socket.
- dashboard_live.ex:311 -- Wrap with `{:noreply, ... |> prepare_assigns()}` like all other inspector handlers.

**CONSTRAINTS**:
- Do NOT modify any other handler functions
- Keep push_event calls for toast notifications

**DEPENDS_ON**: none

## Task 2: Fix dot access to bracket access in teams_components.ex
**FILES**:
- lib/observatory_web/components/teams_components.ex

**CHANGES**:
- Line 67: `@team.name` -> `@team[:name]`
- Line 72: `@team.members` -> `@team[:members] || []`
- Line 88: `@team.name` -> `@team[:name]`

**CONSTRAINTS**:
- Only change dot access to bracket access
- Add `|| []` fallback for members to prevent nil iteration

**DEPENDS_ON**: none

## Task 3: Remove redundant size_class(:maximized) inline styles
**FILES**:
- lib/observatory_web/components/team_inspector_components.ex

**CHANGES**:
- Line 114: Change `defp size_class(:maximized), do: "fixed inset-0 z-40 h-auto"` to just `""` since CSS `.inspector-maximized` handles it with !important

**CONSTRAINTS**:
- Only modify size_class(:maximized)
- Keep the CSS in app.css as-is

**DEPENDS_ON**: none
