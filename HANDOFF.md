# Observatory - Handoff

## Current Status: Fleet View + Messaging Debug (2026-03-07)

### Just Completed
- **Fixed command bar select freeze** -- Select dropdown was inside `phx-update="ignore"`, preventing it from updating when agents come online. Moved select outside, only text input wrapped in `phx-update="ignore"`.
- **Created FleetHelpers module** -- Extracted pure fleet tree functions into `ObservatoryWeb.Components.FleetHelpers` (modular Elixir pattern).
- **3-column fleet view** -- Fleet tree (360px) | Comms timeline (flex) | Detail panel (400px). Teams grouped by project with tree connectors.
- **Messaging architecture doc** -- `docs/messaging-architecture.md` maps all 5 message flow paths, PubSub topics, bypass routes, unification opportunities.

### Key Finding: Messages Not Sending (Root Cause)
The forms and handlers work correctly. When agents are registered in AgentRegistry, delivery succeeds (confirmed via MCP curl). The issue was:
1. No active Claude sessions -> no hook events -> AgentRegistry empty (only "operator")
2. Command bar select was frozen at mount time due to `phx-update="ignore"` -> no agents to select
3. User is now booting a real team which will trigger hook events and populate the registry.

### What's Working
- `Operator.send` -> `Gateway.Router.broadcast` -> `MailboxAdapter` + `Tmux` + `Webhook` pipeline
- MCP tools (check_inbox, send_message, acknowledge_message)
- FleetHelpers: role classification, hierarchy sorting, chain of command, project grouping
- Fleet tree with tree connectors, role badges, project headers
- Comms timeline with team filtering
- Detail panel with chain of command, recent messages, tmux button, direct message form

### What Needs Attention
1. **Gateway unification** -- 5 bypass paths skip Gateway Router (see docs/messaging-architecture.md)
2. **Tmux panel integration** -- User wants multi-tmux view, not just single "Tmux" button
3. **Ash-ify messaging** -- Mailbox/CommandQueue/AgentRegistry are plain GenServers, could use Ash resources
4. **Steps 7-9 of Ash refactor** -- Move inline handlers, retire helpers, final validation (task 9)

### Architecture
- Phoenix LiveView on port 4005
- Event-driven: hooks -> POST /api/events -> EventBuffer ETS + PubSub -> LiveView
- Gateway Router: Validate -> Route -> Deliver -> Audit pipeline
- AgentRegistry: ETS-backed, populated by hook events + TeamWatcher + tmux polling
- Zero warnings: `mix compile --warnings-as-errors`
- Module size limit: 200-300 lines max

### Key Files Modified This Session
| File | Change |
|------|--------|
| `lib/observatory_web/components/fleet_helpers.ex` | Created: pure fleet tree helper functions |
| `lib/observatory_web/components/command_components/command_view.html.heex` | Rewritten: 3-column layout, fixed select freeze |
| `lib/observatory_web/components/command_components.ex` | Added FleetHelpers alias, removed inline helpers |
| `lib/observatory_web/live/dashboard_live.ex` | Added fleet assigns, removed debug logging |
| `docs/messaging-architecture.md` | Created: full messaging architecture map |
