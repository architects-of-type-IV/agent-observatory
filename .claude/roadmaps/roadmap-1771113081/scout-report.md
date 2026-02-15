# Scout Report: Team Inspector Feature

## Consolidated Findings from 4 Parallel Scouts

---

## 1. Adding a New View (Established Pattern)

Adding a view requires:
1. Create `lib/observatory_web/components/{name}_components.ex` with `use Phoenix.Component`, attrs, and `{name}_view/1`
2. Add tab button in `dashboard_live.html.heex` (view-mode-toggle section)
3. Add `:if={@view_mode == :name}` dispatch in template
4. Add data computation in `prepare_assigns/1` if needed
5. Add handler module if view has events
6. No router changes -- all within single LiveView

Convention: atom `:teams`, module `TeamsComponents`, function `teams_view/1`.

## 2. Team Data Available

Teams have: name, description, members, tasks, source, lead_session, dead?
Members have: name, agent_id, agent_type, status, health, model, cwd, current_tool, uptime, failure_rate, event_count
Tasks have: id, subject, status, owner, blocked_by, blocks
Sessions have: session_id, model, status, started_at, ended_at (SQLite)
Events have: session_id, hook_event_type, payload, tool_name, duration_ms (SQLite)

## 3. Messaging Capabilities

**Working:** Dashboard->agent (Mailbox+CommandQueue), agent->agent (MCP), team broadcast (inline in handler)
**Missing:** All-teams broadcast, role-based targeting (lead vs member), server-side team registry

## 4. UI Patterns

- Dark theme: zinc-950 bg, zinc-100 text, indigo accents
- Right-side detail panel: conditional render, w-96, no animation
- **No bottom drawer/panel exists** -- must create new pattern
- Modals: fixed inset-0 overlay + centered container
- Keyboard shortcuts via JS hook
- State persistence via localStorage hook

## 5. Critical Gaps to Address

| Gap | Impact | Solution |
|-----|--------|----------|
| No bottom drawer pattern | Core to Team Inspector UX | Create new CSS/component pattern |
| No server-side team registry | Blocks multi-team messaging | Extract from LiveView assigns or use TeamWatcher |
| No role concept (lead/member) | Blocks targeted messaging | Derive from team config (first member or agent_type) |
| No team-level aggregates | No progress/health rollup | Compute in prepare_assigns |
| No message flow tracking | Can't show inter-agent communication | Derive from SendMessage events |
| No roadmap integration | Can't show team roadmap progress | Read from .claude/roadmaps/ |
