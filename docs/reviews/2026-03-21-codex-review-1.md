    impl().emit(name, scope_id, data)
  end

  @impl true
exec
/bin/zsh -lc "sed -n '1,220p' lib/ichor/factory/completion_handler.ex" in /Users/xander/code/www/kardashev/observatory succeeded in 51ms:
defmodule Ichor.Factory.CompletionHandler do
  @moduledoc """
  Reacts to pipeline completion and dispatches the appropriate build output flow.
  Follows the ProjectIngestor pattern: subscribe to signal, call domain APIs.
  """

  use GenServer

  require Logger

  alias Ichor.Factory.{Pipeline, Project}
  alias Ichor.Factory.PluginLoader
  alias Ichor.Signals

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
exec
/bin/zsh -lc "sed -n '1,220p' lib/ichor/workshop/team_member.ex" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "sed -n '1,220p' lib/ichor/workshop/canvas_state.ex" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "sed -n '1,220p' lib/ichor/infrastructure/team_launch.ex" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "sed -n '1,220p' lib/ichor/infrastructure/agent_process.ex" in /Users/xander/code/www/kardashev/observatory succeeded in 52ms:
defmodule Ichor.Workshop.TeamMember do
  @moduledoc """
  A persisted team member definition for Workshop-authored teams.

  Each member may point at an `AgentType` while still carrying team-specific
  launch overrides like extra instructions, file scope, and tool scope.
  """

  use Ash.Resource,
    domain: Ichor.Workshop,
    data_layer: AshSqlite.DataLayer

  alias Ichor.Workshop.{AgentType, Team}

  sqlite do
    repo(Ichor.Repo)
    table("workshop_team_members")
  end

  attributes do
 succeeded in 51ms:
defmodule Ichor.Workshop.CanvasState do
  @moduledoc """
  Pure state transitions for the Workshop canvas.
  """

  @type agent :: %{
          id: integer(),
          agent_type_id: String.t() | nil,
          name: String.t(),
          capability: String.t(),
          model: String.t(),
          permission: String.t(),
          persona: String.t(),
          file_scope: String.t(),
          quality_gates: String.t(),
          tools: [String.t()],
          x: integer(),
          y: integer()
        }

 succeeded in 51ms:
defmodule Ichor.Infrastructure.TeamLaunch do
  @moduledoc """
  Lifecycle operations for launching and tearing down multi-agent tmux-backed teams.

  Orchestrates the named launch stages:
    1. `TeamLaunch.Scripts`      — write prompt and script files
    2. `TeamLaunch.Session`      — create tmux session and windows
    3. `TeamLaunch.Registration` — register agents in the fleet registry

  On failure, `TeamLaunch.Rollback` cleans up any partially-created resources.
  """

  alias Ichor.Infrastructure.TeamSpec
  alias Ichor.Infrastructure.TeamLaunch.{Registration, Rollback, Scripts, Session}

  @doc "Launch a full multi-agent team: creates tmux session, all windows, and registers all agents."
  @spec launch(TeamSpec.t()) :: {:ok, String.t()} | {:error, term()}
  def launch(%TeamSpec{} = spec) do
    with {:error, reason} <- do_launch(spec) do
      Rollback.teardown(spec)
 succeeded in 52ms:
defmodule Ichor.Infrastructure.AgentProcess do
  @moduledoc """
  A living agent in the fleet. Each agent is a GenServer process with a native
  BEAM mailbox. The process IS the agent -- its PID is the canonical identity,
  its mailbox is the delivery target, its supervision is its lifecycle.

  Backend transport (tmux, SSH, webhook) is handled by `AgentDelivery`.
  Message normalization lives in `AgentMessage`.
  Registry projection logic lives in `AgentRegistryProjection`.
  Lifecycle signal emission lives in `AgentLifecycle`.
  Backend liveness/termination lives in `AgentBackend`.
  Pure state transitions live in `AgentState`.
  """

  use GenServer

  alias Ichor.Infrastructure.AgentBackend
  alias Ichor.Infrastructure.AgentDelivery
  alias Ichor.Infrastructure.AgentLifecycle
  alias Ichor.Infrastructure.AgentRegistryProjection
codex
I have enough of the runtime shape now. I’m doing one last light pass on dependency and system composition, then I’ll write the review with explicit agreements, disagreements, and what I think the current analysis is still missing.
exec
/bin/zsh -lc "sed -n '1,260p' mix.exs" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "rg -n \"Task\\.start\\(|GenServer\\.call\\(|Registry\\.lookup\\(|Ash\\.Changeset\\.for_|Ash\\.(get|read|create|update|destroy)"'!?" lib/ichor | sed -n '"'1,260p'" in /Users/xander/code/www/kardashev/observatoryexec
/bin/zsh -lc "rg -n \"Application.get_env|System\\.cmd|File\\.(read|write|stream|ls|mkdir_p|mkdir_p"'!)|Path'"\\.expand\\(\" lib/ichor | sed -n '1,220p'" in /Users/xander/code/www/kardashev/observatory succeeded in 51ms:
defmodule Ichor.MixProject do
  use Mix.Project

  def project do
    [
      app: :ichor,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      xref: [exclude: xref_excludes()],
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  def application do
 succeeded in 52ms:
lib/ichor/memories_bridge.ex:47:    case Application.get_env(:ichor, :memories) do
lib/ichor/factory/loader.ex:72:    |> File.stream!()
lib/ichor/factory/spawn.ex:180:    case File.ls(TeamSpec.prompt_root_dir(:mes)) do
lib/ichor/factory/spawn.ex:280:    Application.get_env(:ichor, :mes_team_supervisor_module, Ichor.Infrastructure.TeamSupervisor).list_all()
lib/ichor/factory/spawn.ex:284:    Application.get_env(:ichor, :mes_cleanup_module, Ichor.Infrastructure.Cleanup)
lib/ichor/factory/spawn.ex:288:    Application.get_env(:ichor, :mes_tmux_launcher_module, Ichor.Infrastructure.Tmux.Launcher)
lib/ichor/workshop/spawn.ex:299:    Application.get_env(:ichor, :workshop_prompt_root_dir, Path.expand("~/.ichor/workshop"))
lib/ichor/factory/workers/orphan_sweep_worker.ex:47:    Application.get_env(:ichor, Oban, [])
lib/ichor/factory/lifecycle_supervisor.ex:83:    Application.get_env(:ichor, Oban, [])
lib/ichor/workshop/team_spec.ex:146:    do: Application.get_env(:ichor, :mes_prompt_root_dir, Path.expand("~/.ichor/mes"))
lib/ichor/workshop/team_spec.ex:149:    do: Application.get_env(:ichor, :pipeline_prompt_root_dir, Path.expand("~/.ichor/pipeline"))
lib/ichor/workshop/team_spec.ex:152:    do: Application.get_env(:ichor, :planning_prompt_root_dir, Path.expand("~/.ichor/planning"))
lib/ichor/workshop/team_spec.ex:169:    Application.get_env(:ichor, :mes_workshop_team_name, "mes")
lib/ichor/factory/plugin_scaffold.ex:47:    with :ok <- File.mkdir_p(lib_dir),
lib/ichor/factory/plugin_scaffold.ex:68:    case File.write(path, content) do
lib/ichor/factory/runner.ex:352:    Application.get_env(:ichor, :mes_team_launch_module, TeamLaunch)
lib/ichor/factory/runner.ex:487:    mod = Application.get_env(:ichor, :tmux_launcher_module, TmuxLauncher)
lib/ichor/factory/pipeline_monitor.ex:21:  @teams_dir Path.expand("~/.claude/teams")
lib/ichor/factory/pipeline_monitor.ex:22:  @archive_dir Path.expand("~/.claude/teams/.archive")
lib/ichor/factory/pipeline_monitor.ex:23:  @health_check_script Path.expand("~/.claude/skills/swarm/scripts/health-check.sh")
 succeeded in 52ms:
lib/ichor/infrastructure/cron_scheduler.ex:35:    GenServer.call(__MODULE__, {:schedule_once, agent_id, delay_ms, payload})
lib/ichor/factory/pipeline.ex:120:        with {:ok, run} <- Ash.get(__MODULE__, run_id),
lib/ichor/signals/bus.ex:105:        case Registry.lookup(Ichor.Registry, {:agent, id}) do
lib/ichor/infrastructure/host_registry.ex:28:    GenServer.call(__MODULE__, :list_hosts)
lib/ichor/infrastructure/host_registry.ex:34:    GenServer.call(__MODULE__, {:get_host, node_name})
lib/ichor/infrastructure/host_registry.ex:40:    GenServer.call(__MODULE__, {:register, node_name, metadata})
lib/ichor/infrastructure/host_registry.ex:46:    GenServer.call(__MODULE__, {:remove, node_name})
lib/ichor/signals/event_stream.ex:69:    GenServer.call(__MODULE__, {:heartbeat, agent_id, cluster_id})
lib/ichor/signals/event_stream.ex:92:    GenServer.call(__MODULE__, {:get_session_state, session_id})
lib/ichor/infrastructure/team_supervisor.ex:44:    case Registry.lookup(Ichor.Registry, {:agent, agent_id}) do
lib/ichor/infrastructure/team_supervisor.ex:75:    case Registry.lookup(@team_registry, {:team, team_name}) do
lib/ichor/signals/protocol_tracker.ex:32:  def get_stats, do: GenServer.call(__MODULE__, :get_stats)
lib/ichor/factory/project.ex:328:               |> Ash.Changeset.for_create(:create, attrs)
lib/ichor/factory/project.ex:329:               |> Ash.create() do
lib/ichor/factory/project.ex:342:        with {:ok, project} <- Ash.get(__MODULE__, input.arguments.project_id),
lib/ichor/factory/project.ex:346:               |> Ash.Changeset.for_update(:advance, %{planning_stage: planning_stage})
lib/ichor/factory/project.ex:347:               |> Ash.update() do
lib/ichor/factory/project.ex:363:               |> Ash.read() do
lib/ichor/factory/project.ex:375:        with {:ok, project} <- Ash.get(__MODULE__, input.arguments.project_id) do
lib/ichor/factory/project.ex:387:        with {:ok, project} <- Ash.get(__MODULE__, input.arguments.project_id) do

thinking
**Reviewing API design**

I’m noticing that external callers are directly accessing resources, which goes against the established best practices in both the skills and documentation. It's an anti-pattern. I should find some examples of these direct resource calls crossing boundaries. There likely are many, but I might just mention general issues in the review. Also, I think I need to update the plan once I've fully reviewed this situation. Let's see what I can gather!
Plan update
  ✓ Read domain definitions and key Ash resources to verify public boundaries
  ✓ Inspect orchestration/process modules around spawn, runner, signals, watchdogs, and monitoring
  → Synthesize agreements, disagreements, and missing architectural concerns from first principles


thinking
**Evaluating domain modules**

I’m noticing that domain modules mainly consist of catalogs or tool manifests rather than actual business boundaries. While discovery might be fine, the architecture doesn’t seem to be domain-centric. The type discipline looks poor with maps everywhere, and there are unclear identifiers for sessions and statuses. I think we need better-defined structures like RunRef, AgentRef, and TeamRef, along with typed result resources and embedded resources. Plus, it seems like authorization and policies are missing.
thinking
**Considering functional programming principles**

I want to mention more about functional programming principles like pure core and effect edges. The current code has pure modules like CanvasState and Runner.Modes, but there seem to be too many effectful modules mixing decisions with I/O. I’ll need to cite file references in absolute paths, but exact line numbers might not be necessary. I’m thinking about using clickable labels and crafting a flat bullet list since there’ll be no nesting.
codex
**Assessment**

The existing docs are directionally right. The strongest parts of the system are the separation between authored design and runtime launch contracts in [lib/ichor/workshop/team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex), the use of a signal facade in [lib/ichor/signals.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals.ex), and the fact that some core logic is already pure and data-shaped, like [lib/ichor/workshop/canvas_state.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/canvas_state.ex) and [lib/ichor/factory/runner/modes.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner/modes.ex). Those are the most Elixir-native parts: explicit state, pure transforms, effects at the edge.

I also agree with the main findings around `TeamSpec`, `EventStream`, `PipelineMonitor`, and both watchdogs. The code confirms them. `TeamSpec` is carrying caller knowledge it should not own. `EventStream` is not just a store; it performs fleet mutation. `PipelineMonitor` is a serialized mutable cache over recomputable state. `AgentWatchdog` and `TeamWatchdog` both decide and perform cross-domain side effects directly.

**Where I Agree**

- The hidden concept in `TeamSpec` is real. Compilation and prompt strategy are different responsibilities. [lib/ichor/workshop/team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex) should own “design -> runtime contract”, not “MES/planning/pipeline knowledge”.
- Workshop owning persistent team design and Infrastructure owning launch mechanics is the right split. [lib/ichor/workshop/spawn.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/spawn.ex) and [lib/ichor/infrastructure/team_launch.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure/team_launch.ex) show the intended seam clearly.
- Signals are a good cross-boundary integration mechanism. [lib/ichor/workshop/team_spawn_handler.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spawn_handler.ex) is a good example of the pattern actually working.
- The docs are right that `PipelineMonitor` is too process-heavy. [lib/ichor/factory/pipeline_monitor.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/pipeline_monitor.ex) is doing discovery, polling, file IO, health scripts, mutation, and projection in one GenServer.
- The docs are right that several “domains” are not really domains. [lib/ichor/infrastructure.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure.ex) is a host/runtime namespace wearing an Ash Domain costume.

**Where I Disagree Or Would Be Stricter**

- I would not push all coordination into signals. Signals are good for facts crossing bounded contexts. They are not automatically better than a direct call. Overusing them creates event soup and weakens traceability. Within a cohesive subsystem, a direct function call is often clearer.
- I would not force everything toward one generic `spawn/1`. A universal launch primitive is fine, but planning and pipeline still need typed orchestration before launch. The mistake is not having specialized orchestrators. The mistake is letting the compiler own their knowledge.
- I would be harsher on `EventStream` auto-registration than the docs are. Event ingestion mutating runtime topology is a dangerous coupling, not just a pragmatic one. [lib/ichor/signals/event_stream.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream.ex) currently treats incoming events as authority to create/manage fleet entities. I would split “observe event” from “admit runtime identity”.
- I would not keep Infrastructure as an Ash Domain unless there is a real product-facing operational surface with policies and typed actions. Otherwise it should just be plain modules.
- I would not describe the current architecture as truly domain-oriented. The Ash domains are mostly catalogs; the real business API still leaks through resource modules and direct Ash calls.

**What’s Missing From The Current Analysis**

- Ash is underutilized. The codebase uses Ash resources, but not the strongest Ash ideas: policies, domain-owned public interfaces, calculations/aggregates as first-class modeling tools, and typed action surfaces. There are many action-only resources returning opaque `:map` values, which weakens discoverability and composition.
- The boundary problem is bigger than cross-domain calls. It is also “effectful code in the middle of business logic”. Filesystem paths under `~/.claude`, `System.cmd/3`, tmux control, and JSON file mutation are spread through Factory, Signals, Archon, and Infrastructure. The effect boundary is too porous.
- The identifier model is weak. `run_id`, `session`, `session_id`, `team_name`, and agent IDs are stringly typed everywhere. The docs mention `RunSpec` and `AgentId`; I agree, and I think they are more important than the docs suggest.
- There is no clear trust model. Events, tmux state, JSONL files, registry entries, and Ash records all participate in system truth, but the architecture does not make authority explicit.
- Authorization is basically absent as an architectural concern. In an Ash system, that is a major omission.
- [lib/ichor/architecture/boundary_audit.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/architecture/boundary_audit.ex) is mostly a stub right now. The codebase knows it has boundary problems but the enforcement mechanism is not actually encoded.

**What I Would Do Differently**

- Treat Ash as the business modeling layer, not as a thin wrapper around runtime modules. Public business capabilities should be domain-owned and typed. Plain Elixir modules should handle pure transforms. Host/runtime adapters should stay outside Ash unless they need policies, persistence, or discovery exposure.
- Split the system into three clearer strata:
  1. Pure model/compilation/query code.
  2. Application services/orchestrators for planning, pipeline, workshop launch.
  3. Runtime adapters for tmux, files, HTTP hooks, bash scripts.
- Keep signals only for durable cross-context facts: run started, run completed, agent crashed, task claimed, session discovered. Do not use them as the default replacement for ordinary local calls.
- Replace singleton mutable processes with recomputable read models where possible. `PipelineMonitor` is the main candidate.
- Introduce typed value objects immediately: `RunRef`, `SessionRef`, `AgentRef`, `TeamRef`. This would collapse a lot of brittle string parsing and mode branching in [lib/ichor/factory/runner.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner.ex), [lib/ichor/archon/team_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/archon/team_watchdog.ex), and [lib/ichor/signals/agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex).
- Define explicit authorities:
  - Ash resources are authority for durable business state.
  - Runtime registry/processes are authority for live process state.
  - External files are interoperability adapters, not domain truth.
  - Signals carry facts, not ownership.

Net: I agree with most of the current audit, but I think the deeper issue is not just misplaced modules. It is that the codebase has not fully chosen between “Ash as the business boundary” and “plain Elixir/OTP with Ash-shaped facades”. Right now it is in the middle. I would resolve that by making Ash narrower and stronger, and making the runtime layer plainer and more explicit.
tokens used
112.219
**Assessment**

The existing docs are directionally right. The strongest parts of the system are the separation between authored design and runtime launch contracts in [lib/ichor/workshop/team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex), the use of a signal facade in [lib/ichor/signals.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals.ex), and the fact that some core logic is already pure and data-shaped, like [lib/ichor/workshop/canvas_state.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/canvas_state.ex) and [lib/ichor/factory/runner/modes.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner/modes.ex). Those are the most Elixir-native parts: explicit state, pure transforms, effects at the edge.

I also agree with the main findings around `TeamSpec`, `EventStream`, `PipelineMonitor`, and both watchdogs. The code confirms them. `TeamSpec` is carrying caller knowledge it should not own. `EventStream` is not just a store; it performs fleet mutation. `PipelineMonitor` is a serialized mutable cache over recomputable state. `AgentWatchdog` and `TeamWatchdog` both decide and perform cross-domain side effects directly.

**Where I Agree**

- The hidden concept in `TeamSpec` is real. Compilation and prompt strategy are different responsibilities. [lib/ichor/workshop/team_spec.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spec.ex) should own “design -> runtime contract”, not “MES/planning/pipeline knowledge”.
- Workshop owning persistent team design and Infrastructure owning launch mechanics is the right split. [lib/ichor/workshop/spawn.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/spawn.ex) and [lib/ichor/infrastructure/team_launch.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure/team_launch.ex) show the intended seam clearly.
- Signals are a good cross-boundary integration mechanism. [lib/ichor/workshop/team_spawn_handler.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/workshop/team_spawn_handler.ex) is a good example of the pattern actually working.
- The docs are right that `PipelineMonitor` is too process-heavy. [lib/ichor/factory/pipeline_monitor.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/pipeline_monitor.ex) is doing discovery, polling, file IO, health scripts, mutation, and projection in one GenServer.
- The docs are right that several “domains” are not really domains. [lib/ichor/infrastructure.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/infrastructure.ex) is a host/runtime namespace wearing an Ash Domain costume.

**Where I Disagree Or Would Be Stricter**

- I would not push all coordination into signals. Signals are good for facts crossing bounded contexts. They are not automatically better than a direct call. Overusing them creates event soup and weakens traceability. Within a cohesive subsystem, a direct function call is often clearer.
- I would not force everything toward one generic `spawn/1`. A universal launch primitive is fine, but planning and pipeline still need typed orchestration before launch. The mistake is not having specialized orchestrators. The mistake is letting the compiler own their knowledge.
- I would be harsher on `EventStream` auto-registration than the docs are. Event ingestion mutating runtime topology is a dangerous coupling, not just a pragmatic one. [lib/ichor/signals/event_stream.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/event_stream.ex) currently treats incoming events as authority to create/manage fleet entities. I would split “observe event” from “admit runtime identity”.
- I would not keep Infrastructure as an Ash Domain unless there is a real product-facing operational surface with policies and typed actions. Otherwise it should just be plain modules.
- I would not describe the current architecture as truly domain-oriented. The Ash domains are mostly catalogs; the real business API still leaks through resource modules and direct Ash calls.

**What’s Missing From The Current Analysis**

- Ash is underutilized. The codebase uses Ash resources, but not the strongest Ash ideas: policies, domain-owned public interfaces, calculations/aggregates as first-class modeling tools, and typed action surfaces. There are many action-only resources returning opaque `:map` values, which weakens discoverability and composition.
- The boundary problem is bigger than cross-domain calls. It is also “effectful code in the middle of business logic”. Filesystem paths under `~/.claude`, `System.cmd/3`, tmux control, and JSON file mutation are spread through Factory, Signals, Archon, and Infrastructure. The effect boundary is too porous.
- The identifier model is weak. `run_id`, `session`, `session_id`, `team_name`, and agent IDs are stringly typed everywhere. The docs mention `RunSpec` and `AgentId`; I agree, and I think they are more important than the docs suggest.
- There is no clear trust model. Events, tmux state, JSONL files, registry entries, and Ash records all participate in system truth, but the architecture does not make authority explicit.
- Authorization is basically absent as an architectural concern. In an Ash system, that is a major omission.
- [lib/ichor/architecture/boundary_audit.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/architecture/boundary_audit.ex) is mostly a stub right now. The codebase knows it has boundary problems but the enforcement mechanism is not actually encoded.

**What I Would Do Differently**

- Treat Ash as the business modeling layer, not as a thin wrapper around runtime modules. Public business capabilities should be domain-owned and typed. Plain Elixir modules should handle pure transforms. Host/runtime adapters should stay outside Ash unless they need policies, persistence, or discovery exposure.
- Split the system into three clearer strata:
  1. Pure model/compilation/query code.
  2. Application services/orchestrators for planning, pipeline, workshop launch.
  3. Runtime adapters for tmux, files, HTTP hooks, bash scripts.
- Keep signals only for durable cross-context facts: run started, run completed, agent crashed, task claimed, session discovered. Do not use them as the default replacement for ordinary local calls.
- Replace singleton mutable processes with recomputable read models where possible. `PipelineMonitor` is the main candidate.
- Introduce typed value objects immediately: `RunRef`, `SessionRef`, `AgentRef`, `TeamRef`. This would collapse a lot of brittle string parsing and mode branching in [lib/ichor/factory/runner.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/factory/runner.ex), [lib/ichor/archon/team_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/archon/team_watchdog.ex), and [lib/ichor/signals/agent_watchdog.ex](/Users/xander/code/www/kardashev/observatory/lib/ichor/signals/agent_watchdog.ex).
- Define explicit authorities:
  - Ash resources are authority for durable business state.
  - Runtime registry/processes are authority for live process state.
  - External files are interoperability adapters, not domain truth.
  - Signals carry facts, not ownership.

Net: I agree with most of the current audit, but I think the deeper issue is not just misplaced modules. It is that the codebase has not fully chosen between “Ash as the business boundary” and “plain Elixir/OTP with Ash-shaped facades”. Right now it is in the middle. I would resolve that by making Ash narrower and stronger, and making the runtime layer plainer and more explicit.
