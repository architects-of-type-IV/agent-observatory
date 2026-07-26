# fleet_analysis

Health, session, and topology derivation from a fleet's raw event log.

Extracted from the ICHOR IV agent observatory. Pure functions over event lists —
no processes, no storage, no clock of its own. No dependencies.

## The failure modes worth naming

A stuck agent and a looping agent both look perfectly healthy from outside. The
process is up, the tmux pane is open, the supervisor is content, nothing raises.
They are only visible as *shapes in the event log*:

**Stuck** — a gap. No events for longer than the threshold. The agent is alive
and doing nothing.

**Looping** — a repeat. The same tool called three times running. The agent is
busy and making no progress: re-reading a file it already read, retrying a
command that will keep failing. Every liveness measure says it's fine.

**Failing** — a ratio. Most tool calls returning errors. Working, getting
nowhere.

That's why this is a library and not a supervisor callback. OTP can tell you a
process died; it cannot tell you a process is politely spinning.

## What it computes

| Module | From | To |
|---|---|---|
| `FleetAnalysis.Health` | one agent's events | stuck / looping / failing |
| `FleetAnalysis.Sessions` | all events | session summaries |
| `FleetAnalysis.Topology` | sessions + teams | graph nodes and edges |
| `FleetAnalysis.Entry` | — | id and role helpers |

## Install

```elixir
def deps do
  [{:fleet_analysis, path: "../fleet_analysis"}]
end
```

## Use

```elixir
events = MyApp.Events.recent()
now = DateTime.utc_now()

# One agent
FleetAnalysis.health(agent_events, now)
#=> %{health: :critical, issues: [{:stuck, event}], failure_rate: 0.0,
#=>   stuck?: true, loops: []}

# The whole fleet, grouped in one pass
FleetAnalysis.health_by_session(events, now)
FleetAnalysis.unhealthy(events, now)     #=> [{"session-id", health}], worst first

# Sessions and graph
sessions = FleetAnalysis.sessions(events, tmux: TmuxChannel.list_sessions())
{nodes, edges} = FleetAnalysis.topology(sessions, MyApp.Teams.all(), now)
```

`now` is always an argument, never read from the clock. That makes historical
windows possible and tests deterministic.

## Design notes

**Sessions are derived, not stored.** A session is inferred by grouping the
append-only event log on `{source_app, session_id}`. A separately maintained
session table can disagree with what actually happened; a derivation cannot.

**Sessions with no events still appear.** A tmux session that has never emitted
an event is invisible to a pure event query — and a freshly spawned agent that
died before its first event is exactly the case you most want to see. Pass
`:tmux` with the live session names and those show up with zero events.

**Topology merges what ran with what was configured.** A team member that never
started has no session; a session outside any team has no member. Both get
nodes. The gap between them is usually the interesting part: an orphan member
node is an agent that failed to start.

**Stuck and looping outrank failure rate.** A high failure rate often resolves
on its own. Silence and spinning do not.

## Events

Events are whatever the host already has — Ecto schemas, Ash resources, or plain
maps. `FleetAnalysis.Event` documents the fields read:

| Field | Used for |
|---|---|
| `:inserted_at` | Ordering and every staleness calculation |
| `:session_id` | Grouping events into sessions |
| `:hook_event_type` | `:PreToolUse`, `:PostToolUse`, `:PostToolUseFailure`, `:SessionEnd` |
| `:source_app` | Fallback session label |
| `:tool_name` | Loop detection |
| `:payload` / `:model_name` | Model lookup |
| `:cwd`, `:permission_mode`, `:tmux_session` | Carried through |

Every one is optional. An analysis pass over a live log is exactly where partial
records turn up — a truncated write, an older schema, a test fixture — and
crashing the dashboard over one malformed event is the wrong trade.

## Configuration

These are judgement calls about what "unhealthy" means, and the right numbers
depend on what your agents do. An agent running long builds is legitimately
silent for minutes; one that should be answering messages is not.

```elixir
config :fleet_analysis,
  stuck_after_sec: 60,
  idle_after_sec: 120,
  loop_window: 5,
  loop_min_repeats: 3,
  failure_rate_warning: 0.3,
  failure_rate_critical: 0.5
```

## Tests

```
mix test
```

90 tests and 21 doctests covering each failure mode and its thresholds, session
grouping and tmux merging, node and edge construction, and malformed events and
teams throughout.

## Changes from the original

- Namespace `Ichor.Workshop.Analysis.*` → `FleetAnalysis.*`; `Queries` split
  into `Sessions` and `Topology`, and `Workshop.AgentEntry` became
  `FleetAnalysis.Entry`.
- Every threshold moved from module attributes to configuration.
- Event field access goes through `FleetAnalysis.Event`, which tolerates missing
  fields instead of raising.

Fixed along the way:

- **A partial event crashed the analysis.** `e.payload["model"]` and
  `e.model_name` raise `KeyError` on any event map lacking those keys, taking
  down the whole pass — and with it the dashboard — over one bad record.
- **`short_id/1` raised on an empty string.** `String.slice("", 0, 8)` is fine,
  but the UUID guard fell through to returning `""`, rendering a nameless row.
  Empty and non-binary input now give `"?"`.

Added: `health_by_session/2` and `unhealthy/2`, which group the log once instead
of making callers filter it per agent; `Health.stuck?/2` and `detect_loops/1` are
now public, and `Topology.state/2`, `duration/1`, and `short_model/1` were
private helpers worth exposing and testing.
