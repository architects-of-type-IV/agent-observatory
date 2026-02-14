# Observatory Project Knowledge

## Project Structure
Observatory is a Phoenix LiveView application for monitoring Claude Code agent activity in real-time.

### Key Components
1. **DashboardLive** - Main real-time monitoring interface
2. **EventController** - HTTP endpoint for receiving hook events
3. **TeamWatcher** - GenServer watching ~/.claude/teams/ and ~/.claude/tasks/
4. **Ash Resources** - Event and Session data models using AshSqlite

### Architecture Patterns
- **Event streaming**: Uses Phoenix PubSub to broadcast events from controller to LiveView
- **Dual data sources**: Merges event-derived state with disk-based team/task state
- **ETS for performance**: EventController tracks tool execution timing in ETS table
- **Real-time updates**: 1-second timer tick for relative timestamps

### Data Flow
1. Hook events POST to EventController
2. Controller stores in SQLite via Ash, broadcasts to PubSub
3. DashboardLive subscribes to "events:stream" and "teams:update"
4. TeamWatcher polls ~/.claude/teams/ every 2s, broadcasts changes
5. DashboardLive derives team/task state from events, merges with disk state

### UI Interactivity Patterns
**Detail Panel Pattern (Mutually Exclusive Selection)**:
- Right sidebar shows either event detail OR task detail
- Selecting event clears selected_task, selecting task clears selected_event
- Close button (X icon) in panel header clears selection
- Same w-96 aside container reused for both types of details

**View Mode Tabs**:
- 4 view modes: :feed (default), :tasks, :messages, :agents
- Controlled by handle_event("set_view", %{"mode" => mode}, socket)
- Each view mode renders different main content area
- Tab buttons show counts in zinc-600 (tasks count, messages count, teams count)

**Agent Filtering**:
- Clicking agent card sets filter_session_id and switches to :feed view
- Allows drilling down from team overview to specific agent activity
- filter_agent handler: assigns filter_session_id + view_mode: :feed

### Refactoring Insights
**Original dashboard_live.ex (1168 lines):**
- 480 lines of inline HEEx template (lines 682-1162)
- Complex data transformation logic before rendering
- Team derivation from events (scanning for TeamCreate/Task tool events)
- Task reconstruction from TaskCreate/TaskUpdate events
- Event filtering, search, and session tracking
- Multiple view modes (feed, tasks, messages)

**After Full Refactoring (Tasks #1-14 complete):**
- dashboard_live.ex: 216 lines (mount, handle_*, prepare_assigns only)
- dashboard_live.html.heex: 589 lines (external template with 4 views)
- dashboard_helpers.ex: 503 lines (all helper functions + constants)
- observatory_components.ex: 126 lines (reusable function components)
- Total reduction: 82% from original LiveView module

**Helper Extraction Pattern:**
- Move ALL private defp functions to separate helper module
- Move module attributes (@session_palette, @event_type_labels, @team_tools)
- Keep only LiveView callbacks and lifecycle-specific functions
- Import helper module: `import ObservatoryWeb.DashboardHelpers`
- Template automatically loads matching .html.heex file

**Component Extraction Pattern:**
- Create reusable function components for repeated UI patterns
- Use attr/2 macro to define component attributes with types
- Components live in observatory_components.ex module
- Import in template: function components auto-imported when use Phoenix.Component

### Compilation Requirements
- Zero warnings policy enforced
- Use `mix compile --warnings-as-errors` after changes
- Project uses Ash framework with SQLite data layer

### Team/Task State Management
**Dual Source Strategy:**
- Event-derived: TeamCreate/Task tool events parsed into team structs
- Disk-derived: TeamWatcher polls ~/.claude/teams/ for config.json files
- Merge strategy: disk data wins when team exists in both sources
- Task data: Disk tasks prioritized (from ~/.claude/tasks/{team}/*.json)
- Member enrichment: Cross-reference agent_id with events for status/activity
