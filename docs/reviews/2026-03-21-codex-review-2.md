    14	  def spawn_team(name) when is_binary(name) do
    15	    case Team.by_name(name) do
    16	      {:ok, team} ->
    17	        with {:ok, members} <- TeamMember.for_team_with_type(team.id) do
    18	          spawn_team(team, members)
    19	        end
    20	
 succeeded in 50ms:
     1	defmodule Ichor.Workshop.TeamSpec do
     2	  @moduledoc """
     3	  Pure builder for `TeamSpec` and `AgentSpec` runtime contracts across all run modes.
     4	
     5	  Consolidates MES, pipeline, and planning spec construction. Per-mode differences
     6	  (preset name, prompt builder, metadata) are expressed as data, not separate modules.
     7	
     8	  Public API:
     9	    - build(:mes, run_id, team_name)
    10	    - build(:pipeline, run, session, brief, tasks, worker_groups, prompt_ctx)
    11	    - build(:planning, run_id, mode, project_id, planning_project_id, brief)
    12	    - build_corrective(run_id, session, reason, attempt)
    13	    - session_name(run_id) -- MES only
    14	    - prompt_dir(:mes, run_id) | prompt_dir(:pipeline, run_id) | prompt_dir(:planning, run_id, mode)
    15	    - prompt_root_dir(:mes) | prompt_root_dir(:pipeline) | prompt_root_dir(:planning)
    16	  """
    17	
    18	  alias Ichor.Factory.PlanningPrompts
    19	  alias Ichor.Infrastructure.AgentSpec
    20	  alias Ichor.Infrastructure.TeamSpec, as: Spec
 succeeded in 51ms:
     1	defmodule Ichor.Signals.AgentWatchdog do
     2	  @moduledoc """
     3	  Consolidated agent health monitor. Replaces Heartbeat, AgentMonitor,
     4	  NudgeEscalator, and PaneMonitor with a single GenServer and one timer.
     5	
     6	  On every :beat (5s):
     7	    1. Emit heartbeat signal
     8	    2. Detect and handle crashed agents
     9	    3. Advance escalation for stale agents
    10	    4. Scan tmux panes for DONE/BLOCKED signals
    11	
    12	  Subscribes to :events to keep session activity current.
    13	  """
    14	  use GenServer
    15	  require Logger
    16	
    17	  alias Ichor.Factory.Board
    18	  alias Ichor.Infrastructure.AgentProcess
    19	  alias Ichor.Infrastructure.HITLRelay
    20	  alias Ichor.Infrastructure.Tmux
 succeeded in 50ms:
     1	defmodule Ichor.Signals.EventStream do
     2	  @moduledoc """
     3	  Unified event runtime. Canonical owner of the in-memory event buffer,
     4	  session aliases, tombstones, tool duration tracking, and heartbeat liveness.
     5	
     6	  Public API:
     7	  - `ingest_raw/1`           -- normalize a raw hook map, store, and emit signals
     8	  - `record_heartbeat/2`     -- normalize a heartbeat into a trace event, update liveness
     9	  - `publish_fact/2`         -- publish an internal fact (watchdog probes, etc.)
    10	  - `subscribe/2`            -- subscribe to the normalized event stream
    11	  - `latest_session_state/1` -- liveness/alias/last-seen for a session
    12	  - `list_events/0`          -- all buffered events (most recent first)
    13	  - `latest_per_session/0`   -- latest event per session (dashboard seed)
    14	  - `unique_project_cwds/0`  -- unique non-empty cwd values across buffer
    15	  - `events_for_session/1`   -- events for a specific session
    16	  - `remove_session/1`       -- remove session events and tombstone
    17	  - `tombstone_session/1`    -- place a 30s tombstone (drops late events)
    18	  """
    19	
    20	  use GenServer
 succeeded in 51ms:
     1	defmodule Ichor.Signals.EventStream.AgentLifecycle do
     2	  @moduledoc """
     3	  Fleet mutations triggered by hook events. Creates, terminates, and manages
     4	  agent processes in response to event stream data.
     5	
     6	  All functions here represent what a given event means for the fleet --
     7	  resolving/spawning AgentProcess entries, disbanding teams, and handling
     8	  team lifecycle tool calls.
     9	  """
    10	
    11	  require Logger
    12	
    13	  alias Ichor.Infrastructure.{AgentProcess, FleetSupervisor, TeamSupervisor}
    14	
    15	  @doc """
    16	  Resolve or create an AgentProcess for the given session_id and event.
    17	
    18	  Returns the canonical agent id to use for subsequent operations.
    19	  """
    20	  @spec resolve_or_create_agent(String.t(), map()) :: String.t()
 succeeded in 50ms:
     1	defmodule Ichor.Archon.TeamWatchdog do
     2	  @moduledoc """
     3	  Signal-driven team lifecycle monitor. No timers, no polling.
     4	  Reacts to universal run signals and fleet events to detect unexpected deaths,
     5	  archive runs, reset pipeline tasks, and notify operator.
     6	  """
     7	
     8	  use GenServer
     9	
    10	  alias Ichor.Factory.{Pipeline, PipelineTask, Spawn}
    11	  alias Ichor.Infrastructure.FleetSupervisor
    12	  alias Ichor.Signals
    13	  alias Ichor.Signals.Message
    14	
    15	  @inbox_dir Path.expand("~/.claude/inbox")
    16	
    17	  @type action ::
    18	          {:archive_run, String.t()}
    19	          | {:reset_tasks, String.t()}
    20	          | {:notify_operator, String.t()}
 succeeded in 51ms:
     1	defmodule Ichor.Factory.Runner do
     2	  @moduledoc """
     3	  Unified GenServer representing a single run lifecycle.
     4	
     5	  A single data-driven lifecycle process for MES, planning, and pipeline runs.
     6	  Behavioral differences are expressed through `%Runner.Mode{}` config structs
     7	  and hook functions.
     8	
     9	  Registry keys by kind:
    10	    - :mes     -> {:run, run_id}
    11	    - :planning -> {:planning_run, run_id}
    12	    - :pipeline -> {:pipeline_run, run_id}
    13	  """
    14	
    15	  use GenServer, restart: :temporary
    16	
    17	  alias Ichor.Factory.{Pipeline, PipelineGraph, PipelineTask}
    18	  alias Ichor.Factory.Runner.{Exporter, HealthChecker, Modes}
    19	  alias Ichor.Infrastructure.TeamLaunch
    20	  alias Ichor.Infrastructure.Tmux.Launcher, as: TmuxLauncher
 succeeded in 51ms:
     1	defmodule Ichor.Factory.PipelineMonitor do
     2	  @moduledoc """
     3	  Live pipeline board runtime.
     4	
     5	  This is the active GenServer behind project discovery, task refresh,
     6	  health polling, and corrective task actions for `tasks.jsonl` pipelines.
     7	  """
     8	  use GenServer
     9	
    10	  require Logger
    11	
    12	  alias Ichor.Factory.{DateUtils, PipelineGraph}
    13	  alias Ichor.Factory.JsonlStore
    14	  alias Ichor.Infrastructure.Cleanup
    15	  alias Ichor.Signals.EventStream, as: EventBuffer
    16	  alias Ichor.Signals.Message
    17	
    18	  @tasks_poll_interval 3_000
    19	  @health_poll_interval 30_000
    20	

thinking
**Considering registry key cleanup**

I think I should focus on the lower runner lines around the registry key. It seems like cleanup might be necessary as well. I'm not entirely sure what the best approach is for that or what specific steps I should take. It feels a bit unclear, so I’ll need to dig deeper into that. Maybe some research will help clarify what needs to be done for an effective cleanup!
exec
/bin/zsh -lc "nl -ba lib/ichor/factory/runner.ex | sed -n '260,520p'" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "nl -ba lib/ichor/factory/runner/modes.ex | sed -n '1,220p'" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "nl -ba lib/ichor/infrastructure.ex | sed -n '1,120p'" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "nl -ba lib/ichor/signal_bus.ex | sed -n '1,120p'" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "nl -ba lib/ichor/workshop/agent.ex | sed -n '110,360p'" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "nl -ba lib/ichor/factory/floor.ex | sed -n '1,220p'" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "nl -ba lib/ichor/runtime_supervisor.ex | sed -n '1,140p'" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "nl -ba lib/ichor/signals/event_bridge.ex | sed -n '1,340p'" in /Users/xander/code/www/kardashev/observatory succeeded in 51ms:
   260	  def handle_call(:deadline_passed?, _from, state) do
   261	    {:reply, state.deadline_passed, state}
   262	  end
   263	
   264	  @impl true
   265	  def terminate(_reason, state) do
   266	    emit_signal(state.config.signals.terminated, build_terminate_payload(state))
   267	
   268	    Signals.emit(:run_terminated, %{
   269	      kind: state.kind,
   270	      run_id: state.run_id,
   271	      session: state.session
   272	    })
   273	
   274	    :ok
   275	  end
   276	
   277	  # ---------------------------------------------------------------------------
   278	  # Mode configuration — delegates to Runner.Modes
   279	  # ---------------------------------------------------------------------------
 succeeded in 52ms:
     1	defmodule Ichor.Infrastructure do
     2	  @moduledoc """
     3	  Namespace for non-domain infrastructure concerns.
     4	
     5	  This is where runtime adapters and host integrations should move when they
     6	  do not model product concepts. Typical examples are tmux, MCP transport,
     7	  process orchestration, file sync boundaries, and external service adapters.
     8	  """
     9	
    10	  use Ash.Domain, extensions: [AshAi]
    11	
    12	  resources do
    13	    resource(Ichor.Infrastructure.CronJob)
    14	    resource(Ichor.Infrastructure.HITLInterventionEvent)
    15	    resource(Ichor.Infrastructure.Operations)
    16	    resource(Ichor.Infrastructure.WebhookDelivery)
    17	  end
    18	
    19	  tools do
    20	    tool(:system_health, Ichor.Infrastructure.Operations, :system_health)
 succeeded in 52ms:
     1	defmodule Ichor.SignalBus do
     2	  @moduledoc """
     3	  Ash domain for discoverable signal-facing actions.
     4	
     5	  The runtime facade remains `Ichor.Signals`; this domain exists so Discovery
     6	  can enumerate mailbox and other signal actions through Ash.
     7	  """
     8	
     9	  use Ash.Domain, extensions: [AshAi]
    10	
    11	  resources do
    12	    resource(Ichor.Signals.Event)
    13	    resource(Ichor.Signals.Operations)
    14	    resource(Ichor.Signals.TaskProjection)
    15	    resource(Ichor.Signals.ToolFailure)
    16	  end
    17	
    18	  tools do
    19	    tool(:check_operator_inbox, Ichor.Signals.Operations, :check_operator_inbox)
    20	    tool(:check_inbox, Ichor.Signals.Operations, :check_inbox)
 succeeded in 52ms:
     1	defmodule Ichor.Factory.Runner.Modes do
     2	  @moduledoc """
     3	  Pure `%Runner.Mode{}` struct factories.
     4	
     5	  Builds data-driven mode configuration for MES, planning, and pipeline runs.
     6	  Hook function slots that require GenServer-private callbacks are left as `nil`
     7	  and must be filled in by the caller (Runner) via the `runner_hooks` argument.
     8	
     9	  ## Runner hooks keys
    10	
    11	  - `:mes_on_init`       — `fn state -> ... end` called after timers are scheduled
    12	  - `:mes_on_signal`     — `fn msg, state -> state end` for MES signal dispatch
    13	  - `:pipeline_check_stale`  — `fn state -> :ok end` periodic stale-task check
    14	  - `:pipeline_check_health` — `fn state -> :ok end` periodic health-report check
    15	  - `:pipeline_sync_task`    — `fn state, task -> {:noreply, state} end`
    16	  - `:pipeline_on_complete`  — `fn state -> :ok end`
    17	  """
    18	
    19	  alias Ichor.Factory.Runner.Mode
    20	  alias Ichor.Signals
 succeeded in 51ms:
   110	            {:ok, %{"found" => false, "query" => query}}
   111	
   112	          agent ->
   113	            tmux_target = agent.channels[:tmux] || agent.tmux_session
   114	
   115	            tmux_ok =
   116	              if is_binary(tmux_target),
   117	                do: Tmux.available?(tmux_target),
   118	                else: false
   119	
   120	            {:ok,
   121	             %{
   122	               "id" => agent.agent_id,
   123	               "name" => agent.short_name || agent.name || agent.agent_id,
   124	               "session_id" => agent.session_id,
   125	               "team" => agent.team_name,
   126	               "role" => agent.role,
   127	               "status" => agent.status,
   128	               "model" => agent.model,
   129	               "cwd" => agent.cwd,
 succeeded in 51ms:
     1	defmodule Ichor.Factory.Floor do
     2	  @moduledoc "Action-only Factory control surface for board operations and MES control."
     3	
     4	  use Ash.Resource, domain: Ichor.Factory
     5	
     6	  alias Ichor.Factory.{Board, MesScheduler, Runner, Spawn}
     7	  alias Ichor.Workshop.ActiveTeam
     8	
     9	  actions do
    10	    action :get_tasks, {:array, :map} do
    11	      description("Get assigned tasks from the Factory task board.")
    12	
    13	      argument :session_id, :string do
    14	        allow_nil?(false)
    15	      end
    16	
    17	      argument :team_name, :string do
    18	        allow_nil?(false)
    19	        default("")
    20	      end
 succeeded in 51ms:
     1	defmodule Ichor.RuntimeSupervisor do
     2	  @moduledoc """
     3	  Supervises independent runtime services under a single one_for_one supervisor.
     4	  """
     5	  use Supervisor
     6	
     7	  @doc false
     8	  @spec start_link(keyword()) :: Supervisor.on_start()
     9	  def start_link(opts) do
    10	    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    11	  end
    12	
    13	  @impl true
    14	  def init(_opts) do
    15	    children = [
    16	      # Core infrastructure services
    17	      {Ichor.MemoryStore, []},
    18	      {Ichor.Signals.EventStream, []},
    19	
    20	      # Infrastructure and signal-adjacent services
 succeeded in 51ms:
     1	defmodule Ichor.Signals.EventBridge do
     2	  @moduledoc """
     3	  Bridges the events:stream into gateway:messages by transforming
     4	  persisted event records into DecisionLog format.
     5	
     6	  Subscribes to "events:stream" and broadcasts the transformed
     7	  DecisionLog on "gateway:messages" so the dashboard's gateway
     8	  handlers receive live data from all Claude Code sessions.
     9	
    10	  Also manages per-session DAG topology subscriptions (formerly
    11	  TopologyBuilder). When a new session is seen, EventBridge
    12	  subscribes to "session:dag:<id>" and emits a topology_snapshot
    13	  signal on each dag_delta event.
    14	  """
    15	
    16	  use GenServer
    17	
    18	  alias Ichor.Mesh.CausalDAG
    19	  alias Ichor.Mesh.DecisionLog
    20	  alias Ichor.Mesh.DecisionLog.Helpers, as: DLHelpers

thinking
**Considering project size**

I think I should inspect the project size. It feels like the project might be huge. If it’s big, the architecture review might highlight the need for substantial resources. I might want to use a command like `wc -l` to get an idea of the number of lines in the project, which could give me a sense of its size. This could be helpful in understanding what I’m dealing with.
exec
/bin/zsh -lc 'wc -l lib/ichor/factory/project.ex lib/ichor/workshop/team_spec.ex lib/ichor/factory/pipeline_monitor.ex lib/ichor/signals/agent_watchdog.ex lib/ichor/factory/runner.ex lib/ichor/workshop/agent.ex lib/ichor/signals/event_stream.ex' in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "nl -ba lib/ichor/factory/project.ex | sed -n '520,980p'" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "nl -ba lib/ichor/factory/project.ex | sed -n '300,520p'" in /Users/xander/code/www/kardashev/observatory succeeded in 51ms:
     971 lib/ichor/factory/project.ex
     394 lib/ichor/workshop/team_spec.ex
     623 lib/ichor/factory/pipeline_monitor.ex
     487 lib/ichor/signals/agent_watchdog.ex
     577 lib/ichor/factory/runner.ex
     426 lib/ichor/workshop/agent.ex
     401 lib/ichor/signals/event_stream.ex
    3879 total
 succeeded in 52ms:
   300	      argument(:title, :string, allow_nil?: false)
   301	      argument(:description, :string, allow_nil?: false)
   302	      argument(:brief, :string, allow_nil?: false, default: "")
   303	      argument(:output_kind, :string, allow_nil?: false, default: "plugin")
   304	      argument(:plugin, :string, allow_nil?: false, default: "")
   305	      argument(:signal_interface, :string, allow_nil?: false, default: "")
   306	      argument(:topic, :string, allow_nil?: false, default: "")
   307	      argument(:run_id, :string, allow_nil?: false, default: "")
   308	      argument(:team_name, :string, allow_nil?: false, default: "")
   309	
   310	      run(fn input, _context ->
   311	        args = input.arguments
   312	
   313	        attrs =
   314	          %{
   315	            title: args.title,
   316	            description: args.description,
   317	            artifacts: brief_artifacts(args.title, blank_to_nil(args.brief)),
   318	            output_kind: args.output_kind
   319	          }
 succeeded in 52ms:
   520	      end)
   521	    end
   522	
   523	    action :list_adrs, {:array, :map} do
   524	      description("List ADRs for a project.")
   525	
   526	      argument(:project_id, :string, allow_nil?: false)
   527	
   528	      run(fn input, _context ->
   529	        list_artifacts_for(input.arguments.project_id, :adr, [:code, :title, :status])
   530	      end)
   531	    end
   532	
   533	    action :create_feature, :map do
   534	      description("Create a feature artifact for a project.")
   535	
   536	      argument(:project_id, :string, allow_nil?: false)
   537	      argument(:code, :string, allow_nil?: false)
   538	      argument(:title, :string, allow_nil?: false)
   539	      argument(:content, :string, allow_nil?: false, default: "")







thinking
**Planning architectural review**

I need to inspect the Signal runtime to mention the use of a facade. For the architectural review, I should focus on findings first since a developer indicated that this is the default approach when a review is requested. The structure might include sections like Key Conclusions, Agree, Disagree, and Missed/What I'd Do Differently. I want to ensure it’s concise but detailed enough, maybe using four sections and ordering findings by severity with absolute file references for clarity.
thinking
**Highlighting key findings**

I'll start with the most severe findings. First, there are two competing sources of truth in the runtime—Ash domains versus the OTP/filesystem. Ash is being used for action wrappers instead of as an ownership model, which could cause confusion. Second, EventStream and EventBridge have too many responsibilities. EventStream alters the fleet upon ingestion, which isn’t ideal; event ingestion shouldn’t control fleet mutations. Third, there's duplication between TeamSpec and Spawn. It's good to separate compile and launch, but prompt content should stay in the code for now.
thinking
**Discussing project findings**

I’m noticing some issues with the PipelineMonitor GenServer, as it seems to be incorrectly serializing reads and writes from files. The external interop adapter should handle pulling and querying, rather than being a long-lived mutable process. Also, the TeamWatchdog side-effect dispatcher appears to be brittle, with direct calls across domains causing potential problems. Lastly, the Project resource is overly large—Factory.Project is 971 lines and combines too many elements. This concern wasn’t emphasized enough in the documentation.
thinking
**Evaluating orchestration modules**

I'm considering resources and orchestration modules. In Ash, the domains feel thin, and I don't think they should serve as a dumping ground. I think this "data-driven" Runner concept maybe sounds good but might overstate how generic it is. There’s still hardcoded logic that could complicate matters. I also disagree with some proposed changes, such as moving watchdogs or enforcing strict cross-domain call restrictions. Signals should be used for asynchronous effects, and generic spawning may oversimplify things.
thinking
**Analyzing orchestration and code structure**

I'm trying to keep the compile and launch processes generic while still addressing explicit use cases and entry points. I see some positives, like the effective use of plain modules for transformations, such as Runner.Modes and PipelineGraph. Also, embedded resources for artifacts and the roadmap are a plus. There's a solid code interface, and the separation of infrastructure execution in TeamLaunch is nice too. However, I think there's a need for a stronger functional core and explicit read models. Plus, the registry and supervision tree could benefit from value objects.
thinking
**Reviewing event buffer and semantics**

I'm thinking about separating projection modules from being treated as canonical resources, especially with the event buffer, ActiveTeam, and Agent load from runtime. There's a need for better failure semantics and idempotency regarding jobs, possibly using signals with Oban. I also see a requirement for clearer guidelines on when to use Ash resources versus plain modules. The current codebase leans on Ash for discovery rather than domain modeling, and that contradiction in documentation needs addressing, particularly with the `Ichor.Infrastructure` and `Ash.Domain` use.
thinking
**Drafting static architecture review**

Okay, so the docs call it SignalBus, which is good to know. I might mention that `Workshop.Agent` has four overlapping spawn actions. Also, `Factory.Floor` returns string-keyed maps and directly interacts with GenServers/files, but as an action-only control surface, this could be acceptable. I want to ensure the final document isn’t too lengthy—aiming for about 45 lines with flat bullets. I’ll start with findings and include sections for agreement or disagreement, but I won't run the app since this is just a static review.
codex
**Key Findings**
- The biggest real architectural problem is that runtime ownership is split across Ash, OTP processes, ETS, tmux, and filesystem adapters without one clear rule for who is authoritative. `EventStream` is an event store that also creates and terminates fleet entries ([event_stream.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream.ex#L52), [agent_lifecycle.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream/agent_lifecycle.ex#L20)). `PipelineMonitor` is both read model, discovery service, polling scheduler, and command handler ([pipeline_monitor.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/pipeline_monitor.ex#L1)). That is the core source of drift and coupling.
- `Workshop.TeamSpec` is not just “large”; it owns multiple separate concerns: workshop compilation, MES/pipeline/planning presets, prompt selection, session naming, prompt directory conventions, and runtime metadata ([team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex#L27), [team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex#L81), [team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex#L113)). I agree this should be split, and I agree prompt strategy should come from the caller or an injected strategy module.
- The watchdogs are doing too much synchronous operational work. `AgentWatchdog` mutates board state, writes operator inbox files, and pauses HITL directly ([agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex#L149), [agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex#L162), [agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex#L183), [agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex#L304)). `TeamWatchdog` archives runs, resets tasks, disbands teams, kills sessions, and writes notifications itself ([team_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/archon/team_watchdog.ex#L49), [team_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/archon/team_watchdog.ex#L131), [team_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/archon/team_watchdog.ex#L167)). That should become decision emission plus idempotent handlers/jobs.
- `Factory.Project` is a more important “god module” than the documents emphasize. It is 971 lines and mixes schema, embedded-content CRUD, project lifecycle, prompt-ish rendering, and view shaping ([project.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/project.ex#L300), [project.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/project.ex#L474), [project.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/project.ex#L849)). In Ash terms, this is where the codebase is closest to using a resource as a dumping ground.
- The “data-driven Runner” story is directionally good but still only half true. `Runner` and `Runner.Modes` reduce duplication, but kind-specific branching still exists in registry keys, supervisors, session naming, hooks, and completion semantics ([runner.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner.ex#L422), [runner.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner.ex#L430), [runner_modes.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner/modes.ex#L32), [runner_modes.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner/modes.ex#L104)). I would not chase full genericity past this point unless you first simplify the actual run model.

**What I Agree With**
- The documents are right that `Workshop.Spawn` and `Workshop.TeamSpec` should converge on one compilation path. The duplication is real ([spawn.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/spawn.ex#L95)).
- They are right that prompts should stay in code for now. A strategy/module binding is much better than storing large prompt templates in DB rows.
- They are right that `RunSpec` and `AgentId`-style value objects would pay off. Too much meaning is encoded in strings today.
- They are right that `PipelineMonitor` is a bad GenServer candidate. Most of its state is recomputable and most of its work is polling external files/scripts.
- They are right that post-commit side effects belong in notifiers/jobs more than in action bodies. `Ichor.Signals.FromAsh` is one of the better architectural moves already present ([from_ash.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/from_ash.ex#L1)).

**What I Disagree With**
- “No direct cross-domain calls” is too absolute. In Elixir, explicit function calls are often better than turning everything into pub/sub. Use signals for asynchronous reactions, retries, fan-out, and decoupled observers. Do not replace every synchronous dependency with hidden event choreography.
- I would not spend much energy on namespace churn like moving `EventBridge` or renaming `EventStream` before fixing ownership boundaries. Those are cleanup tasks, not architectural leverage.
- I do not fully buy the document’s claim that `Infrastructure` must not be an Ash domain. The code already uses it as a discoverable admin surface ([infrastructure.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure.ex#L1)). That can be valid. The problem is not “Ash domain vs namespace”; the problem is unclear ownership and too many action-only façades.
- I would be careful with the vision of one generic `spawn(team_name)` for everything. Compile-and-launch can be generic. Business orchestration should not be. Factory still needs explicit preflight orchestration for planning and pipeline runs.

**What I Think You Missed**
- The codebase needs a written decision rule for three shapes: Ash resource, plain module, long-lived process. Right now Ash is sometimes true domain modeling, sometimes RPC façade, and sometimes discovery metadata. That ambiguity is causing many of the downstream debates.
- `Workshop.Agent` is an example of API sprawl that the docs notice only partially: it exposes overlapping spawn/launch actions with different semantics and return shapes ([agent.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent.ex#L140), [agent.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent.ex#L231), [agent.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent.ex#L295), [agent.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent.ex#L344)). That is a public-surface problem, not just a discovery-description problem.
- `Factory.Floor` and several action-only resources are effectively thin controllers returning ad hoc maps ([floor.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/floor.ex#L9)). That is not inherently wrong, but it means Ash is being used as a tool protocol layer as much as a domain layer. You should make that explicit and design for it.
- Supervision topology deserves more attention. `RuntimeSupervisor` mixes memory, event ingestion, monitoring, pipeline board polling, and Archon processes under one `one_for_one` bucket ([runtime_supervisor.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/runtime_supervisor.ex#L14)). That works, but it hides restart-domain boundaries.

**What I’d Do Differently**
- Define ownership first: `Workshop` owns design-time team definitions, `Factory` owns project and run records, `Infrastructure` owns runtime execution, `Signals` owns broadcast/projection contracts. Then forbid “store + mutate another subsystem” modules.
- Split runtime into command side and projection side. Commands launch/kill/update. Projections build read models from signals/events. `EventStream` and `PipelineMonitor` are currently mixing both.
- Keep Ash for stable business entities and discoverable tool surfaces. Keep pure transformations in plain modules. Keep OTP only for genuinely stateful runtimes. That aligns better with both Elixir and Ash than pushing everything toward one abstraction.
- Treat signals as an integration boundary, not as a universal substitute for function calls.
- Refactor by leverage order: `TeamSpec`, `PipelineMonitor`, `TeamWatchdog`/`AgentWatchdog`, then `Factory.Project`, then naming cleanup.

Static review only; I did not run the app or tests.
tokens used
157.449
**Key Findings**
- The biggest real architectural problem is that runtime ownership is split across Ash, OTP processes, ETS, tmux, and filesystem adapters without one clear rule for who is authoritative. `EventStream` is an event store that also creates and terminates fleet entries ([event_stream.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream.ex#L52), [agent_lifecycle.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream/agent_lifecycle.ex#L20)). `PipelineMonitor` is both read model, discovery service, polling scheduler, and command handler ([pipeline_monitor.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/pipeline_monitor.ex#L1)). That is the core source of drift and coupling.
- `Workshop.TeamSpec` is not just “large”; it owns multiple separate concerns: workshop compilation, MES/pipeline/planning presets, prompt selection, session naming, prompt directory conventions, and runtime metadata ([team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex#L27), [team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex#L81), [team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex#L113)). I agree this should be split, and I agree prompt strategy should come from the caller or an injected strategy module.
- The watchdogs are doing too much synchronous operational work. `AgentWatchdog` mutates board state, writes operator inbox files, and pauses HITL directly ([agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex#L149), [agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex#L162), [agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex#L183), [agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex#L304)). `TeamWatchdog` archives runs, resets tasks, disbands teams, kills sessions, and writes notifications itself ([team_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/archon/team_watchdog.ex#L49), [team_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/archon/team_watchdog.ex#L131), [team_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/archon/team_watchdog.ex#L167)). That should become decision emission plus idempotent handlers/jobs.
- `Factory.Project` is a more important “god module” than the documents emphasize. It is 971 lines and mixes schema, embedded-content CRUD, project lifecycle, prompt-ish rendering, and view shaping ([project.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/project.ex#L300), [project.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/project.ex#L474), [project.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/project.ex#L849)). In Ash terms, this is where the codebase is closest to using a resource as a dumping ground.
- The “data-driven Runner” story is directionally good but still only half true. `Runner` and `Runner.Modes` reduce duplication, but kind-specific branching still exists in registry keys, supervisors, session naming, hooks, and completion semantics ([runner.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner.ex#L422), [runner.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner.ex#L430), [runner_modes.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner/modes.ex#L32), [runner_modes.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner/modes.ex#L104)). I would not chase full genericity past this point unless you first simplify the actual run model.

**What I Agree With**
- The documents are right that `Workshop.Spawn` and `Workshop.TeamSpec` should converge on one compilation path. The duplication is real ([spawn.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/spawn.ex#L95)).
- They are right that prompts should stay in code for now. A strategy/module binding is much better than storing large prompt templates in DB rows.
- They are right that `RunSpec` and `AgentId`-style value objects would pay off. Too much meaning is encoded in strings today.
- They are right that `PipelineMonitor` is a bad GenServer candidate. Most of its state is recomputable and most of its work is polling external files/scripts.
- They are right that post-commit side effects belong in notifiers/jobs more than in action bodies. `Ichor.Signals.FromAsh` is one of the better architectural moves already present ([from_ash.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/from_ash.ex#L1)).

**What I Disagree With**
- “No direct cross-domain calls” is too absolute. In Elixir, explicit function calls are often better than turning everything into pub/sub. Use signals for asynchronous reactions, retries, fan-out, and decoupled observers. Do not replace every synchronous dependency with hidden event choreography.
- I would not spend much energy on namespace churn like moving `EventBridge` or renaming `EventStream` before fixing ownership boundaries. Those are cleanup tasks, not architectural leverage.
- I do not fully buy the document’s claim that `Infrastructure` must not be an Ash domain. The code already uses it as a discoverable admin surface ([infrastructure.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure.ex#L1)). That can be valid. The problem is not “Ash domain vs namespace”; the problem is unclear ownership and too many action-only façades.
- I would be careful with the vision of one generic `spawn(team_name)` for everything. Compile-and-launch can be generic. Business orchestration should not be. Factory still needs explicit preflight orchestration for planning and pipeline runs.

**What I Think You Missed**
- The codebase needs a written decision rule for three shapes: Ash resource, plain module, long-lived process. Right now Ash is sometimes true domain modeling, sometimes RPC façade, and sometimes discovery metadata. That ambiguity is causing many of the downstream debates.
- `Workshop.Agent` is an example of API sprawl that the docs notice only partially: it exposes overlapping spawn/launch actions with different semantics and return shapes ([agent.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent.ex#L140), [agent.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent.ex#L231), [agent.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent.ex#L295), [agent.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/agent.ex#L344)). That is a public-surface problem, not just a discovery-description problem.
- `Factory.Floor` and several action-only resources are effectively thin controllers returning ad hoc maps ([floor.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/floor.ex#L9)). That is not inherently wrong, but it means Ash is being used as a tool protocol layer as much as a domain layer. You should make that explicit and design for it.
- Supervision topology deserves more attention. `RuntimeSupervisor` mixes memory, event ingestion, monitoring, pipeline board polling, and Archon processes under one `one_for_one` bucket ([runtime_supervisor.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/runtime_supervisor.ex#L14)). That works, but it hides restart-domain boundaries.

**What I’d Do Differently**
- Define ownership first: `Workshop` owns design-time team definitions, `Factory` owns project and run records, `Infrastructure` owns runtime execution, `Signals` owns broadcast/projection contracts. Then forbid “store + mutate another subsystem” modules.
- Split runtime into command side and projection side. Commands launch/kill/update. Projections build read models from signals/events. `EventStream` and `PipelineMonitor` are currently mixing both.
- Keep Ash for stable business entities and discoverable tool surfaces. Keep pure transformations in plain modules. Keep OTP only for genuinely stateful runtimes. That aligns better with both Elixir and Ash than pushing everything toward one abstraction.
- Treat signals as an integration boundary, not as a universal substitute for function calls.
- Refactor by leverage order: `TeamSpec`, `PipelineMonitor`, `TeamWatchdog`/`AgentWatchdog`, then `Factory.Project`, then naming cleanup.

Static review only; I did not run the app or tests.
