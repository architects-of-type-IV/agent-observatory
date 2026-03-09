# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Archon Chat UI (2026-03-09)

### Just Completed

1. **Archon LLM wiring** (task 48):
   - `Observatory.Archon.Chat` module: stateless conversation engine
   - LangChain + ChatAnthropic + AshAi tools integration
   - `chat/2` returns `{:ok, response, history}`, history lives in LiveView assigns
   - 10 Ash tools across 5 resources (Agents, Teams, Messages, System, Memory)

2. **Archon chat UI** (task 49, in progress):
   - Keyboard shortcut `a` toggles Archon overlay
   - Floating action button (bottom-right) with amber theme
   - Full-screen overlay: shortcodes panel (left) + chat panel (right)
   - Modular component architecture: `ArchonComponents` with 8 sub-components
   - CSS design system: `archon-*` classes in `app.css` for theme portability
   - Async chat via `Task.start` + `handle_info({:archon_response, result})`
   - `phx-update="ignore"` on input form (prevents timer-tick clearing)
   - `ScrollBottom` JS hook for auto-scroll on new messages
   - Escape key closes overlay

### Architecture Decisions
- **Modular components**: ArchonComponents uses sub-components (shortcodes_panel, chat_panel, chat_bubble, etc.)
- **CSS-first theming**: All Archon styles as `archon-*` CSS components using `@apply`, not inline Tailwind
- **Async LLM calls**: Chat dispatched via Task to avoid blocking LiveView process
- **Stateless chat engine**: No GenServer -- history stored in LiveView assigns (`archon_messages`, `archon_history`)

### .env Setup
- `ANTHROPIC_API_KEY` in `.env` at project root
- No auto-loading (no dotenvy/direnv) -- must `source .env` before `mix phx.server`
- `.env` added to `.gitignore`

### User Directives (this session)
- Build modular: components in components
- DRY CSS: Tailwind component classes for theme portability
- Small template files: componentize all HTML
- Use Ash Resources guide for handlers/actions/LiveViews

### Prior Work (this session)
- Space attribute on Memories resources (Episode, Entity, Fact)
- Zep-aligned episode type/source enums
- MemoriesClient + Memory tools integration
- AgentRegistry decomposition

### Next Steps
1. **Test Archon chat end-to-end** -- verify with live API key
2. **AgentSpawner refactor** -- 318 lines, over 200-line limit

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`

### Build Status
Observatory: `mix compile --warnings-as-errors` clean.
