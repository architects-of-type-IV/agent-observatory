# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Archon Domain + AgentTools Refactor (2026-03-08)

### Just Completed: Archon Domain + Tool Splits

1. **Archon domain** -- the Architect's agent interface to ICHOR IV
   - `Observatory.Archon` parent domain (for future resources)
   - `Observatory.Archon.Tools` subdomain with AshAi (7 tools)
   - 4 focused resources: Agents, Teams, Messages, System
   - All in-process calls (no HTTP overhead) to AgentRegistry, TeamWatcher, Mailbox, Tmux

2. **AgentTools refactor** -- split 2 bloated files (726 lines) into 7 focused resources (498 lines)
   - Inbox (check, acknowledge, send), Tasks, Memory (core ops), Recall, Archival, Agents
   - Domain uses alias pattern, all resources under 120 lines

3. **NudgeEscalator fix** -- skip operator agent (role: :operator) from stale detection
   - Operator is the Architect (human), not an autonomous agent
   - Was being escalated to zombie (level 3) every time

4. **Killed rogue scheduled task** -- PID 15813, Claude session sending "ping the coordinators of active teams" every 60s

5. **Disabled SQL query debug log** -- `log: false` in dev.exs Repo config

### Prior: Workshop Refactor + Ash-Disciplined Refactor (Phases 1-7)

### Remaining
- **Memories integration** -- read Zep docs, test Memories API from Observatory, wire into Archon tools
- **Archon LLM** -- connect Archon to Claude API with AshAi tools
- **Archon chat UI** -- dashboard drawer/panel for conversing with Archon
- **Phase 8**: ICHOR IV rename (deferred -- Archon will be built as a real agent, not a rename of Operator)

### Build Status
`mix compile --warnings-as-errors` clean.
