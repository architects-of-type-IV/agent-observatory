# MES -- Manufacturing Execution System

The MES is ICHOR IV's autonomous subsystem factory. It spawns agent teams that
research, design, and produce project briefs for new subsystems. Approved briefs
become standalone Mix projects that get hot-loaded into the running BEAM VM.

## Pipeline

```
Scheduler (cron)
  -> TeamSpawner (5 agents in tmux)
    -> Researchers (web search, ideas)
    -> Planner (synthesize brief)
    -> Coordinator (deliver to operator)
  -> Archon (floor manager, creates Project record)
  -> Builder agent (picks up brief, writes Mix project)
  -> SubsystemLoader (compile + hot-load into VM)
  -> Subsystem is live, auto-wired via info/0
```

## Architecture

### Supervision Tree

```
Ichor.Mes.Supervisor (rest_for_one)
  |-- Ichor.Mes.RunSupervisor (DynamicSupervisor for RunProcesses)
  |-- Ichor.Mes.Janitor (monitors RunProcesses, guaranteed cleanup)
  |-- Ichor.Mes.ProjectIngestor (signal listener, auto-creates Projects)
  |-- Ichor.Mes.Scheduler (periodic team spawning)
```

### Key Modules

| Module | Role |
|--------|------|
| `Ichor.Mes.Scheduler` | Spawns teams on interval. Max 1 concurrent (tunable). |
| `Ichor.Mes.RunProcess` | GenServer per run. 10-minute kill timer. |
| `Ichor.Mes.TeamSpawner` | Creates tmux session with 5 agent windows. Registers agents in Fleet. |
| `Ichor.Mes.Janitor` | Monitors RunProcesses via `Process.monitor/1`. Cleans up teams/tmux on `:DOWN`. Periodic sweep every 2min. |
| `Ichor.Mes.Project` | Ash Resource (SQLite). Lifecycle: proposed -> in_progress -> compiled -> loaded (or failed). |
| `Ichor.Mes.ProjectIngestor` | Subscribes to `:messages` signals. Auto-creates Project records from agent deliveries. |
| `Ichor.Mes.SubsystemLoader` | Compiles standalone Mix project, hot-loads only `Ichor.Subsystems.*` BEAM modules. |
| `Ichor.Mes.Subsystem` | Behaviour contract: `info/0`, `start/0`, `handle_signal/1`, `stop/0`. |
| `Ichor.Mes.Subsystem.Info` | Struct returned by `info/0`. The uniform manifest for auto-discovery. |

### Archon Tools (Floor Manager)

Archon has 5 MES tools exposed as Ash actions in `Ichor.Archon.Tools.Mes`:

| Tool | What it does |
|------|-------------|
| `list_projects` | List all project briefs, optionally filter by status |
| `create_project` | Create a new project brief with full Info struct fields |
| `check_operator_inbox` | Read messages from MES agents addressed to "operator" |
| `mes_status` | Active runs, scheduler state, team counts |
| `cleanup_mes` | Force cleanup of orphaned teams and tmux sessions |

## Agent Team (5 roles)

Each MES run spawns 5 Claude agents in a tmux session `mes-{run_id}`:

| Agent | Role | Permissions |
|-------|------|-------------|
| coordinator | Orchestrates flow, delivers final brief to operator | read/write/spawn |
| lead | Directs researchers, forwards to planner | read/write/spawn |
| planner | Synthesizes research into structured brief | read/write |
| researcher-1 | Web research on assigned topic | read-only + web |
| researcher-2 | Web research on different topic | read-only + web |

Communication is pull-based via `check_inbox` / `send_message` MCP tools.
Agents are prompted with "YOUR FIRST ACTION RIGHT NOW" to prevent idle starts.

## Project Brief Format

The planner outputs a structured brief matching `Ichor.Mes.Subsystem.Info`:

```
TITLE: Short descriptive name
DESCRIPTION: One or two sentences
SUBSYSTEM: Elixir module name (e.g. Ichor.Subsystems.PulseMonitor)
SIGNAL_INTERFACE: How signals control it
TOPIC: Unique PubSub topic (e.g. subsystem:pulse_monitor)
VERSION: 0.1.0
FEATURES: Comma-separated capability descriptions
USE_CASES: Comma-separated concrete scenarios
ARCHITECTURE: Internal structure description
DEPENDENCIES: Required Ichor modules
SIGNALS_EMITTED: Signal atoms this subsystem emits
SIGNALS_SUBSCRIBED: Signal atoms/categories it listens to
```

## Subsystem Plugin Contract

Every subsystem implements `Ichor.Mes.Subsystem` and returns a uniform
`Info` struct from `info/0`. This is the auto-discovery mechanism:

```elixir
@behaviour Ichor.Mes.Subsystem

@impl true
def info do
  %Ichor.Mes.Subsystem.Info{
    name: "Pulse Monitor",
    module: __MODULE__,
    description: "Real-time signal frequency analyzer",
    topic: "subsystem:pulse_monitor",       # <- the subsystem's address
    version: "0.1.0",
    signals_emitted: [:pulse_anomaly_detected],
    signals_subscribed: [:all],
    features: ["Sliding-window frequency histogram", ...],
    use_cases: ["Detect signal storms", ...],
    dependencies: [Ichor.Signals, :ets]
  }
end

@impl true
def start, do: # start GenServer, subscribe to topic

@impl true
def handle_signal(message), do: # process incoming signal

@impl true
def stop, do: # cleanup
```

The `topic` field is the subsystem's unique PubSub address. The system
routes signals to it. The `info/0` return is what makes auto-discovery work --
every subsystem describes itself identically.

## Standalone Mix Projects

Subsystems live in `subsystems/{name}/` as standalone Mix projects.

### Structure

```
subsystems/pulse_monitor/
  mix.exs                          # app: :pulse_monitor, deps: []
  lib/
    pulse_monitor.ex               # Main module (Ichor.Subsystems.PulseMonitor)
    ichor/
      mes/subsystem.ex             # Stub behaviour (for standalone compilation)
      mes/subsystem/info.ex        # Stub struct
      signals.ex                   # Stub Signals/Catalog/Topics/Message
      pub_sub.ex                   # Stub PubSub
```

### Why stubs?

The subsystem references `Ichor.Mes.Subsystem`, `Ichor.Signals`, etc. These
exist in the host VM but aren't available when compiling standalone. Stubs
provide the minimal type/behaviour definitions so `mix compile` passes.

At runtime, the `SubsystemLoader` only loads `Ichor.Subsystems.*` modules --
stubs are never loaded into the host VM. The real Ichor modules are already
there.

### Building

```bash
cd subsystems/pulse_monitor
mix compile --warnings-as-errors
```

### Hot-Loading

From the host VM (or via dashboard "Load into BEAM" button):

```elixir
project = Ichor.Mes.Project.list_all!() |> Enum.find(& &1.subsystem == "Ichor.Subsystems.PulseMonitor")
Ichor.Mes.SubsystemLoader.compile_and_load(project)
# => {:ok, [Ichor.Subsystems.PulseMonitor]}
```

The loader:
1. Runs `mix compile --warnings-as-errors` in the subsystem directory
2. Finds the ebin directory in `_build/dev/lib/{app}/ebin/`
3. Filters to only `Ichor.Subsystems.*` modules (skips all stubs)
4. Loads via `:code.load_abs/1` (BEAM hot code loading)

### BEAM Hot Code Loading Safety

The BEAM keeps 2 versions of each module: **current** and **old**. Loading a
new version promotes it to current, demotes the previous to old. Processes
running old code continue until they make a fully qualified call
(`Module.function()`), which switches to current. GenServers do this
automatically on every callback.

Loading a third version purges old and terminates any processes still in it.

## Cleanup & GC

### Janitor (OTP-correct cleanup)

`terminate/2` is NOT guaranteed -- brutal kills and supervisor `max_restarts`
skip it. The Janitor uses `Process.monitor/1` for guaranteed cleanup:

- On `:DOWN` from a RunProcess: disbands Fleet team, kills tmux session
- Periodic sweep every 2 minutes: cleans orphaned teams and tmux sessions
- Rebuilds monitors on restart (handles Janitor crashes)

### What gets cleaned up

- Fleet team (FleetSupervisor.disband_team)
- tmux session (kill-session)
- Prompt files (~/.ichor/mes/{run_id}/)

## Dashboard

The MES view (keyboard shortcut in dashboard) shows:
- Scheduler status (tick count, active runs)
- Project list with status badges (Proposed/Building/Compiled/Loaded/Failed)
- "Pick Up" button for proposed projects
- "Load into BEAM" button for compiled projects
- Build log display for failed projects

## Configuration

| Setting | Location | Current Value |
|---------|----------|---------------|
| Max concurrent teams | `Ichor.Mes.Scheduler` `@max_concurrent` | 1 |
| Kill timeout | `Ichor.Mes.RunProcess` `@kill_timeout_ms` | 10 minutes |
| Janitor sweep interval | `Ichor.Mes.Janitor` `@sweep_interval` | 2 minutes |
| Subsystems directory | `Ichor.Mes.SubsystemLoader` `@subsystems_dir` | `subsystems/` |
| Prompt files | `Ichor.Mes.TeamSpawner` `@prompt_dir` | `~/.ichor/mes/` |
| tmux socket | `Ichor.Mes.TeamSpawner` `@ichor_socket` | `~/.ichor/tmux/obs.sock` |

## Signals

MES emits signals in the `:mes` category:

| Signal | When |
|--------|------|
| `mes_team_ready` | Team spawned successfully |
| `mes_team_spawn_failed` | Team spawn failed |
| `mes_team_killed` | Team killed (timeout or manual) |
| `mes_cycle_timeout` | 10-minute deadline reached |
| `mes_project_created` | Project record created |
| `mes_project_picked_up` | Project claimed by builder |
| `mes_subsystem_loaded` | Subsystem hot-loaded into VM |
| `mes_janitor_init` | Janitor started, rebuilt monitors |
| `mes_janitor_cleaned` | Janitor cleaned up a run |
| `mes_janitor_error` | Cleanup error (logged, not fatal) |
| `mes_cleanup` | Orphaned resource cleaned |
| `mes_prompts_written` | Agent prompt files written |
| `mes_tmux_*` | tmux session/window lifecycle |
| `mes_agent_registered` | Agent registered in Fleet |

## Experiment: Pulse Monitor

First end-to-end test (experiment-001):

1. Created project brief with full Info struct fields
2. Built standalone Mix project at `subsystems/pulse_monitor/`
3. Hot-loaded into VM -- only `Ichor.Subsystems.PulseMonitor` loaded (stubs skipped)
4. `info/0` returns correct manifest
5. Host modules intact (12 signal categories verified)

The Pulse Monitor is a real subsystem: GenServer + ETS, sliding-window frequency
histograms, burst/silence detection, signal-driven architecture.
