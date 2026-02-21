---
id: FRD-004
title: SwarmMonitor and ProtocolTracker Services Functional Requirements
date: 2026-02-21
status: draft
source_adr: [ADR-007, ADR-001, ADR-005]
related_rule: []
---

# FRD-004: SwarmMonitor and ProtocolTracker Services

## Purpose

This document specifies the functional requirements for two GenServer processes that back the Swarm Control Center: `Observatory.SwarmMonitor` and `Observatory.ProtocolTracker`. SwarmMonitor is responsible for discovering project roots from active team configuration, reading `tasks.jsonl` pipeline state, computing DAG health metrics, detecting stale and conflicting tasks, and exposing operational actions (heal, reassign, GC). ProtocolTracker subscribes to the event stream and maintains end-to-end message traces across the four communication protocols used by agents: HTTP webhook events, PubSub broadcasts, Mailbox ETS, and CommandQueue filesystem.

Both GenServers are introduced because TeamWatcher, which polls `~/.claude/teams/` and `~/.claude/tasks/`, does not read `tasks.jsonl` and therefore has no pipeline state. ADR-007 governs the design, rationale, and PubSub topic contracts for both processes.

## Functional Requirements

### FR-4.1: SwarmMonitor Process Identity and Supervision

`Observatory.SwarmMonitor` MUST be registered under its own module name via `GenServer.start_link(__MODULE__, opts, name: __MODULE__)` and MUST be started as a supervised child in `Observatory.Application` using the `:one_for_one` strategy. The process MUST appear in the supervision tree after `Observatory.TeamWatcher` and before `Observatory.ProtocolTracker` so that team data is available before SwarmMonitor's first poll completes.

**Positive path**: The application supervisor starts SwarmMonitor by calling `start_link/1`, which executes `init/1`. The process is registered under `Observatory.SwarmMonitor` and is reachable via `GenServer.call(Observatory.SwarmMonitor, :get_state)`.

**Negative path**: If SwarmMonitor crashes it MUST be restarted automatically by the supervisor. Callers that invoke client API functions while the process is restarting will receive `{:error, :noproc}` or a timeout; the dashboard LiveView handles this gracefully by retaining the previous `:swarm_state` assign.

---

### FR-4.2: Project Discovery from Team Member cwd

SwarmMonitor MUST discover project roots by reading all `~/.claude/teams/*/config.json` files and extracting the `cwd` field from each member entry. The derived project key MUST be `Path.basename(cwd)` (the final directory component of the working directory). SwarmMonitor MUST also scan `~/.claude/teams/.archive/*/config.json` to expose archived teams. Both sources are merged into `watched_projects`, a map of `%{key => absolute_path}`.

Project discovery MUST be re-executed on every `:poll_tasks` cycle (every 3 seconds). Newly discovered projects are merged into the existing `watched_projects` map without evicting projects already present. The active project is preserved across re-discoveries as long as its key still exists in the merged map; if it does not, the active project falls back to the first available key.

**Positive path**: A team config at `~/.claude/teams/my-team/config.json` contains a member with `"cwd": "/Users/xander/code/my-project"`. SwarmMonitor computes key `"my-project"` and path `/Users/xander/code/my-project`. On the next poll, `tasks.jsonl` is read from `/Users/xander/code/my-project/tasks.jsonl`.

**Negative path**: If no `config.json` files exist or all member entries lack a `cwd` field, `watched_projects` is an empty map. SwarmMonitor sets `active_project` to `nil`. All subsequent calls to client API functions that require an active project return `{:error, :no_active_project}`.

---

### FR-4.3: Task Polling Interval and Scheduling

SwarmMonitor MUST poll `tasks.jsonl` every 3,000 milliseconds (defined as `@tasks_poll_interval 3_000`). The poll MUST be self-scheduling: `init/1` sends `:poll_tasks` immediately, and each `handle_info(:poll_tasks, state)` clause schedules the next poll via `Process.send_after(self(), :poll_tasks, @tasks_poll_interval)` before performing any work. Health checks MUST be performed on a separate 30,000 millisecond interval (`@health_poll_interval 30_000`), with the first health check deferred by 5,000 milliseconds after startup.

**Positive path**: After startup, `:poll_tasks` fires immediately and then recurs every 3 seconds. The health check fires at 5 seconds and then recurs every 30 seconds. Both cycles run independently; a slow health check MUST NOT delay a task poll.

**Negative path**: If `Process.send_after/3` is not called inside `handle_info(:poll_tasks, state)`, polling stops after the first cycle. This MUST NOT happen. Any exception inside `handle_info` MUST be caught so the schedule is always re-established.

---

### FR-4.4: tasks.jsonl Parsing and Task Normalization

When the active project has a `tasks.jsonl` file, SwarmMonitor MUST stream the file line-by-line, parse each line as JSON using `Jason.decode/1`, and normalize each decoded map into a struct with the following keys: `id`, `status`, `subject`, `description`, `owner`, `priority`, `blocked_by`, `files`, `done_when`, `updated`, `notes`, `tags`. String fields default to `""` when absent; list fields default to `[]`. Tasks with `status == "deleted"` MUST be rejected before any computation. The `updated` field MUST fall back to the `created` field when `updated` is absent.

**Positive path**: A valid `tasks.jsonl` line `{"id":"1","status":"in_progress","subject":"Fix bug","updated":"2026-02-21T12:00:00Z","files":["lib/foo.ex"]}` produces a normalized map with all defaults applied for absent fields.

**Negative path**: Lines that fail `Jason.decode/1` (malformed JSON) produce `nil` and MUST be rejected via `Enum.reject(&is_nil/1)`. A missing or empty `tasks.jsonl` file produces an empty task list, which is valid and results in an empty pipeline struct.

---

### FR-4.5: Pipeline Aggregation

After parsing, SwarmMonitor MUST compute a `pipeline` map with the following integer fields: `total`, `pending`, `in_progress`, `completed`, `failed`, `blocked`. Each field is the count of tasks whose `status` matches the field name. `total` is the count of all non-deleted tasks.

**Positive path**: A list of 10 tasks with statuses `[pending, pending, in_progress, in_progress, in_progress, completed, completed, failed, blocked, blocked]` produces `%{total: 10, pending: 2, in_progress: 3, completed: 2, failed: 1, blocked: 2}`.

**Negative path**: When no tasks exist (empty list), all fields are 0. The `pipeline` key in state MUST never be `nil`.

---

### FR-4.6: DAG Computation (Waves, Edges, Critical Path)

SwarmMonitor MUST derive a `dag` map with three fields: `waves`, `edges`, and `critical_path`. `edges` is a list of `{blocker_id, dependent_id}` tuples derived from each task's `blocked_by` list. `waves` is a list of lists of task IDs computed by topological sort: wave 0 contains tasks with no dependencies, wave N contains tasks whose all dependencies are in earlier waves. Tasks with circular or unresolvable dependencies are collected into a final wave. `critical_path` is the list of task IDs forming the longest dependency chain, computed via memoized DFS. The wave computation MUST cap at 50 iterations to prevent infinite loops.

**Positive path**: Tasks `[A, B->A, C->A, D->B, D->C]` produce waves `[[A], [B, C], [D]]`, edges `[{A,B}, {A,C}, {A,D}, ... ]`, and critical path `[A, B, D]` or `[A, C, D]` (either is correct for equal-length chains).

**Negative path**: If all tasks have no `blocked_by` entries, all tasks appear in wave 0. If tasks have mutually circular dependencies (A blocked_by B, B blocked_by A), both appear in a terminal wave rather than causing an infinite loop.

---

### FR-4.7: Stale Task Detection

SwarmMonitor MUST identify stale tasks as those with `status == "in_progress"` whose `updated` timestamp is more than 10 minutes in the past relative to `DateTime.utc_now()`. Tasks with an empty or unparseable `updated` field MUST be treated as stale (staleness assumed when timestamp cannot be determined). The stale threshold for automated detection is fixed at 10 minutes; the `reset_all_stale/1` client function accepts a configurable `threshold_min` integer for manual overrides.

**Positive path**: A task last updated at `2026-02-21T11:00:00Z` when `now` is `2026-02-21T11:15:00Z` is stale and appears in `state.stale_tasks`.

**Negative path**: A task with an empty `updated` field is conservatively treated as stale. A task with `status == "completed"` is never stale regardless of its timestamp.

---

### FR-4.8: File Conflict Detection

SwarmMonitor MUST compute `file_conflicts` as a list of `{task_id_a, task_id_b, shared_files}` tuples. Two in-progress tasks conflict when their `files` lists share at least one element. Only pairs where `task_a.id < task_b.id` (lexicographic order) are reported, preventing duplicate reporting of the same pair.

**Positive path**: Tasks `A` (files: `["lib/foo.ex", "lib/bar.ex"]`) and `B` (files: `["lib/bar.ex"]`) both in progress produce `{A.id, B.id, ["lib/bar.ex"]}`.

**Negative path**: If both tasks have empty `files` lists, no conflict is reported. Conflicts between completed or pending tasks are not reported.

---

### FR-4.9: Health Check Execution

SwarmMonitor MUST execute an external health check script at `~/.claude/skills/swarm/scripts/health-check.sh` via `System.cmd/3` with the active project path and threshold `"10"` as arguments. The script output MUST be parsed as JSON. A successful health report produces a `health` map with keys `healthy` (boolean), `issues` (list of maps with `type`, `severity`, `task_id`, `owner`, `description`, `details`), `agents` (map), and `timestamp` (current `DateTime.utc_now()`). If the script is absent or returns a non-zero exit code, the health state MUST be left unchanged.

**Positive path**: The script returns exit 0 with JSON `{"healthy": true, "issues": {"details": []}, "agents": {}}`. The `health` map is updated and broadcast via PubSub.

**Negative path**: If `@health_check_script` does not exist on disk, `do_health_check/1` returns the unchanged state. No crash or warning is emitted for a missing script (File.exists? check guards the System.cmd call).

---

### FR-4.10: Operational Actions (Heal, Reassign, Reset Stale, GC, Claim)

SwarmMonitor MUST expose the following client API functions, each implemented as a synchronous `GenServer.call`:

- `heal_task/1` -- resets a task's status to `"pending"` and clears its owner field via `jq` in-place mutation of `tasks.jsonl`.
- `reassign_task/2` -- changes a task's `owner` field without altering its status.
- `reset_all_stale/1` -- identifies all stale in-progress tasks and resets each to `pending` with cleared owner; returns `{:ok, count}` where count is the number of tasks reset.
- `trigger_gc/1` -- calls `~/.claude/skills/dag/scripts/gc.sh` with the team name and `tasks.jsonl` path; returns `{:ok, output}` or `{:error, output}`.
- `claim_task/2` -- calls `~/.claude/skills/dag/scripts/claim-task.sh`; returns `:ok` when the script output contains `"CLAIMED"`.
- `set_active_project/1` -- switches the active project to the given key; returns `{:error, :unknown_project}` for unknown keys.
- `add_project/2` -- registers a project manually by key and path; the path MUST exist as a directory or already contain a `tasks.jsonl`.

All mutation actions MUST call `refresh_tasks/1` and `broadcast/1` after completing the mutation so that the dashboard LiveView receives an updated state.

**Positive path**: `heal_task("3")` rewrites the `tasks.jsonl` line for task `"3"` setting status `"pending"` and owner `""`, then broadcasts `{:swarm_state, state}` on `"swarm:update"`.

**Negative path**: Any action called when `active_project` is `nil` returns `{:error, :no_active_project}` without attempting a file write. `jq` command failures return `{:error, reason_string}` and the state is refreshed regardless.

---

### FR-4.11: SwarmMonitor PubSub Broadcasting

SwarmMonitor MUST broadcast its full state on the `"swarm:update"` PubSub topic via `Phoenix.PubSub.broadcast(Observatory.PubSub, "swarm:update", {:swarm_state, state})`. Broadcasts MUST occur: (1) after every task poll cycle when tasks or projects changed, (2) after every health check, and (3) after every mutation action. The dashboard LiveView MUST subscribe to `"swarm:update"` in `mount/3` and update `:swarm_state` in the corresponding `handle_info/2` clause.

**Positive path**: The dashboard mounts and calls `Observatory.SwarmMonitor.get_state()` for the initial assign. Subsequent changes arrive as `{:swarm_state, state}` messages and are applied via `assign(socket, :swarm_state, state)`.

**Negative path**: If PubSub is not started before SwarmMonitor (wrong supervision order), `broadcast/1` will crash. The supervision order in `application.ex` MUST place `{Phoenix.PubSub, name: Observatory.PubSub}` before `{Observatory.SwarmMonitor, []}`.

---

### FR-4.12: ProtocolTracker Process Identity and ETS Table

`Observatory.ProtocolTracker` MUST be registered under its own module name and supervised alongside SwarmMonitor in `application.ex`. On `init/1`, ProtocolTracker MUST create an ETS table named `:protocol_traces` as `[:named_table, :public, :set]` and subscribe to the `"events:stream"` PubSub topic. The table is public so `get_traces/0` can read it without a GenServer call.

**Positive path**: After startup, `:ets.info(:protocol_traces)` returns a non-nil result. `get_traces/0` queries the table directly and returns traces sorted by timestamp descending.

**Negative path**: If ProtocolTracker crashes, the ETS table is destroyed (named tables are owned by the creating process). On restart, `init/1` re-creates the table, losing previous traces. This is acceptable because traces are ephemeral observability data, not persistent state.

---

### FR-4.13: Trace Creation from Events

ProtocolTracker MUST create a trace entry in the ETS table for the following hook event types arriving on `"events:stream"`:

1. `PreToolUse` events where `tool_name == "SendMessage"` -- creates a `:send_message` trace with `from` set to `event.session_id`, `to` extracted from `payload["tool_input"]["recipient"]` or `payload["tool_input"]["target_agent_id"]`, and an initial hop `%{protocol: :http, status: :received, detail: "PreToolUse/SendMessage"}`.
2. `PreToolUse` events where `tool_name == "TeamCreate"` -- creates a `:team_create` trace with `to: "system"` and content preview from `payload["tool_input"]["team_name"]`.
3. `SubagentStart` events -- creates an `:agent_spawn` trace with `to` extracted from `payload["subagent_id"]`.

All other event types MUST be silently ignored. The trace `id` MUST be the event's `tool_use_id` when present, or a randomly generated 8-byte hex string when absent.

**Positive path**: A `PreToolUse` event for `SendMessage` with `tool_use_id: "abc123"` and `tool_input: %{"recipient": "worker-a", "content": "hello", "type": "message"}` produces a trace with `id: "abc123"`, `type: :send_message`, `to: "worker-a"`, and one hop with `protocol: :http`.

**Negative path**: A `PostToolUse` event for `Bash` MUST be silently dropped; no trace is created and `state.trace_count` is not incremented.

---

### FR-4.14: Hop Appending via Cast

ProtocolTracker MUST expose two cast-based integration points for external modules to append hops to existing traces:

- `track_mailbox_delivery/3` -- appends a hop `%{protocol: :mailbox, status: :delivered}` to the trace identified by `message_id`.
- `track_command_write/2` -- appends a hop `%{protocol: :command_queue, status: :pending}` to the trace identified by `command_id`.

If no trace with the given ID exists in the ETS table, the update MUST be silently ignored.

**Positive path**: After `Observatory.Mailbox` delivers a message with `message_id` matching an existing trace ID, it calls `ProtocolTracker.track_mailbox_delivery(message_id, to, from)`. The trace gains a second hop `%{protocol: :mailbox, status: :delivered, at: <now>}`.

**Negative path**: `track_mailbox_delivery/3` called with an ID not present in `:protocol_traces` is a no-op; no crash occurs.

---

### FR-4.15: Trace Pruning

ProtocolTracker MUST prune the ETS table when its size exceeds 200 entries (`@max_traces 200`). Pruning MUST remove the oldest traces (sorted ascending by `timestamp`) until the count is at or below the limit. Pruning MUST be called synchronously inside `insert_trace/1` after every new entry.

**Positive path**: When the table contains 201 entries after a new insert, the oldest 1 entry is deleted, leaving exactly 200.

**Negative path**: If `prune_traces/0` is not called, the table grows without bound. This degrades `get_traces/0` performance. The 200-entry cap MUST be enforced on every insert.

---

### FR-4.16: ProtocolTracker Stats Computation and Broadcasting

ProtocolTracker MUST compute a `stats` map every 5,000 milliseconds (`@stats_interval 5_000`) and broadcast it on the `"protocols:update"` PubSub topic as `{:protocol_update, stats}`. The stats map MUST include: `traces` (total trace count), `by_type` (frequency map keyed by trace type atom), `mailbox` (`%{agents: count, total_pending: integer}` from `Observatory.Mailbox.get_stats()`), `command_queue` (`%{sessions: count, total_pending: integer}` from `Observatory.CommandQueue.get_queue_stats()`), `mailbox_detail` (raw `Mailbox.get_stats()` list), and `queue_detail` (raw `CommandQueue.get_queue_stats()` list). The dashboard LiveView MUST subscribe to `"protocols:update"` and update `:protocol_stats` on receipt.

**Positive path**: The dashboard assigns `:protocol_stats` with the latest stats on every 5-second broadcast. The Protocols view tab renders counts from this assign.

**Negative path**: If `Observatory.Mailbox` or `Observatory.CommandQueue` is not started, their `get_stats` calls return empty lists rather than crashing ProtocolTracker, because both GenServers are started before ProtocolTracker in the supervision tree.

---

## Out of Scope (Phase 1)

- Persistent storage of traces across restarts (traces are ephemeral ETS data only).
- SwarmMonitor writing to `tasks.jsonl` formats other than JSONL (no YAML or TOML support).
- ProtocolTracker tracing of native Elixir/Phoenix internal messages (only agent hook events are traced).
- Automatic agent restart or process kill initiated by SwarmMonitor health checks.
- Distributed ETS or multi-node support for either GenServer.

## Related ADRs

- [ADR-007](../../decisions/ADR-007-swarm-monitor-design.md) -- SwarmMonitor and ProtocolTracker GenServer Design; defines process separation, PubSub topics, and project discovery strategy.
- [ADR-001](../../decisions/ADR-001-swarm-control-center-nav.md) -- Swarm Control Center Navigation; defines the UI that consumes SwarmMonitor and ProtocolTracker data.
- [ADR-005](../../decisions/ADR-005-ets-over-database.md) -- ETS for Messaging over Database; establishes ETS as the storage medium for ProtocolTracker traces.
