---
id: ADR-011
title: Handler Delegation Pattern for LiveView
date: 2026-02-14
status: accepted
related_tasks: []
parent: null
superseded_by: null
---
# ADR-011 Handler Delegation Pattern for LiveView
[2026-02-14] accepted

## Related ADRs
- [ADR-010](ADR-010-component-file-split.md) Component File Split Pattern

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Team Inspector Design | [CONV-003](../conversations/CONV-003-team-inspector.md) | Handler delegation emerged during Sprint 2, scaled in Sprint 3-4 |
| Session JSONL (inspector) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/8585be9e-149a-4133-bed8-ef55dd380dc9.jsonl` | Raw session transcript |
| Session JSONL (architect) | `~/.claude/projects/-Users-xander-code-www-kardashev-observatory/3b9cd554-74a4-46c3-9db6-6d15f99fc615.jsonl` | Architect validation session |

### Key Moments

| Timestamp | What was discussed |
|-----------|-------------------|
| 2026-02-14 | Sprint 2: handler delegation pattern established (task_handlers, navigation_handlers, session_helpers) |
| 2026-02-15 | Sprint 3-4: handler count scaled from 3 to 6, pattern confirmed to hold at scale |
| 2026-02-15T00:17:42Z | Architect validation: component-handler alignment identified as critical |

## Context

`dashboard_live.ex` started as a monolithic LiveView module handling all `handle_event` and `handle_info` clauses. As features grew, the module exceeded 300 lines and became a merge conflict hotspot when parallel agents edited it.

## Decision

Delegate `handle_event` clauses to domain-specific handler modules:
- `dashboard_messaging_handlers.ex` -- message send/receive
- `dashboard_task_handlers.ex` -- task CRUD operations
- `dashboard_navigation_handlers.ex` -- cross-view navigation jumps
- `dashboard_ui_handlers.ex` -- view mode switching, drawer toggling
- `dashboard_filter_handlers.ex` -- search and filter operations
- `dashboard_notification_handlers.ex` -- notification management

Handler modules return `socket` (not `{:noreply, socket}`) to allow the `prepare_assigns()` wrapper in `dashboard_live.ex`.

Pattern: `Module.handle_event(e, p, s) |> then(&{:noreply, prepare_assigns(&1)})`

## Rationale

- **Module size:** Keeps `dashboard_live.ex` under 300 lines (reduced from 313 to 245 via single-line handler consolidation)
- **Parallel editing:** Non-overlapping file scopes eliminate merge conflicts when multiple agents work simultaneously
- **Domain cohesion:** Each handler module owns one concern (messaging, tasks, navigation, etc.)
- **Scalability:** Started with 3 handlers, grew to 6. Pattern holds without structural changes.

## Consequences

- `dashboard_live.ex` is lifecycle-only: mount, handle_info, handle_event dispatch, prepare_assigns
- Handler modules imported into dashboard_live.ex for simple delegation
- Navigation handlers use guard clause: `when e in ["jump_to_timeline", ...]`
- Single-line consolidation format: `def handle_event("filter", p, s), do: {:noreply, handle_filter(p, s) |> prepare_assigns()}`
- **Lesson learned:** Component-handler alignment is critical. Agent-created components that use wrong event names, attrs, or data shapes require rework.
