defmodule Ichor.Factory.Runner do
  @moduledoc """
  Unified GenServer representing a single run lifecycle.

  A single data-driven lifecycle process for MES, planning, and pipeline runs.
  Behavioral differences are expressed through `%Runner.Mode{}` config structs
  and hook functions.

  Registry keys by kind:
    - :mes     -> {:run, run_id}
    - :planning -> {:planning_run, run_id}
    - :pipeline -> {:pipeline_run, run_id}
  """

  use GenServer, restart: :temporary

  alias Ichor.Factory.{Pipeline, PipelineGraph, PipelineTask, ResearchContext, RunRef}
  alias Ichor.Factory.Runner.{Exporter, HealthChecker, Modes}
  alias Ichor.Infrastructure.Tmux.Launcher, as: TmuxLauncher
  alias Ichor.Orchestration.TeamLaunch
  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Workshop.TeamSpec

  @stale_threshold_min 10

  defmodule Mode do
    @moduledoc "Data-driven configuration for a Runner kind."

    @enforce_keys [:kind, :subscriptions, :signals, :cleanup]
    defstruct [
      :kind,
      # [:messages] | [:mes]
      :subscriptions,
      # %{liveness_ms: 30_000, deadline_ms: nil, ...}
      :timers,
      # %{source: :signal | :message_delivered, ...}
      :completion,
      # [%{id: :health, every_ms: 30_000, callback: fun}]
      :checks,
      # %{policy: :teardown | :mes_maintenance}
      :cleanup,
      # %{ready: atom, completed: atom, tmux_gone: atom, terminated: atom}
      :signals,
      # %{sync_task: fun | nil}
      :commands,
      # %{on_signal: fun | nil, on_complete: fun | nil}
      :hooks
    ]

    @type t :: %__MODULE__{
            kind: :mes | :planning | :pipeline,
            subscriptions: [atom()],
            timers: map() | nil,
            completion: map() | nil,
            checks: [map()] | nil,
            cleanup: map(),
            signals: map(),
            commands: map() | nil,
            hooks: map() | nil
          }
  end

  defmodule State do
    @moduledoc "Internal lifecycle state for a unified Runner process."

    @enforce_keys [:run_id, :kind, :session, :config]
    defstruct [
      :run_id,
      :kind,
      :session,
      :team_spec,
      :project_id,
      :project_path,
      :config,
      :status,
      :started_at,
      deadline_passed: false,
      timers: %{},
      runtime: %{}
    ]

    @type t :: %__MODULE__{
            run_id: String.t(),
            kind: :mes | :planning | :pipeline,
            session: String.t(),
            team_spec: struct() | nil,
            project_id: String.t() | nil,
            project_path: String.t() | nil,
            config: Ichor.Factory.Runner.Mode.t(),
            status: atom() | nil,
            started_at: DateTime.t() | nil,
            deadline_passed: boolean(),
            timers: map(),
            runtime: map()
          }
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    kind = Keyword.fetch!(opts, :kind)
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(kind, run_id))
  end

  @doc "Returns the via-tuple for Registry-based name lookup."
  @spec via(:mes | :planning | :pipeline, String.t()) ::
          {:via, Registry, {Ichor.Registry, {atom(), String.t()}}}
  def via(kind, run_id),
    do: {:via, Registry, {Ichor.Registry, {RunRef.registry_key(kind), run_id}}}

  @doc "Returns the pid for the given kind and run_id if alive, or nil."
  @spec lookup(:mes | :planning | :pipeline, String.t()) :: pid() | nil
  def lookup(kind, run_id) do
    case Registry.lookup(Ichor.Registry, {RunRef.registry_key(kind), run_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Lists all active run IDs and PIDs for the given kind."
  @spec list_all(:mes | :planning | :pipeline) :: [{String.t(), pid()}]
  def list_all(kind) do
    key = RunRef.registry_key(kind)

    Registry.select(Ichor.Registry, [
      {{{key, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc "Starts a new Runner under the appropriate DynamicSupervisor."
  @spec start(:mes | :planning | :pipeline, keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start(kind, opts) do
    supervisor = RunRef.supervisor(kind)
    DynamicSupervisor.start_child(supervisor, {__MODULE__, [kind: kind] ++ opts})
  end

  @doc "Enqueues a write-through sync task. Pipeline-kind only."
  @spec sync_task(String.t(), struct() | map()) :: :ok
  def sync_task(run_id, task),
    do: GenServer.cast(via(:pipeline, run_id), {:command, :sync_task, [task]})

  @doc "Returns true if the run's deadline has passed, or if the process is no longer alive."
  @spec deadline_passed?(pid()) :: boolean()
  def deadline_passed?(pid) do
    GenServer.call(pid, :deadline_passed?, 1_000)
  catch
    :exit, _ -> true
  end

  @doc "Returns a status map for the given kind and run_id."
  @spec status(:mes | :planning | :pipeline, String.t()) :: map() | nil
  def status(kind, run_id) do
    case lookup(kind, run_id) do
      nil -> nil
      pid -> GenServer.call(pid, :status)
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    kind = Keyword.fetch!(opts, :kind)
    run_id = Keyword.fetch!(opts, :run_id)
    config = Modes.build(kind, run_id, opts, runner_hooks())

    state = %State{
      run_id: run_id,
      kind: kind,
      session: session_for(kind, run_id, opts),
      team_spec: Keyword.get(opts, :team_spec),
      project_id: Keyword.get(opts, :project_id),
      project_path: Keyword.get(opts, :project_path),
      config: config,
      started_at: DateTime.utc_now()
    }

    Ichor.Events.subscribe_all()
    schedule_timers(config.timers, state)
    schedule_checks(config.checks)

    {:ok, state}
  end

  @impl true
  def handle_info(:check_liveness, state) do
    session = state.session

    if tmux_available?(session) do
      schedule_liveness(state.config.timers)
      {:noreply, state}
    else
      emit_signal(state.config.signals.tmux_gone, %{
        run_id: state.run_id,
        session: session
      })

      run_cleanup(state)
      {:stop, :normal, state}
    end
  end

  def handle_info(:deadline, state) do
    emit_signal(state.config.signals[:deadline_reached], %{
      run_id: state.run_id,
      team_name: Map.get(state.runtime, :team_name)
    })

    {:noreply, %{state | deadline_passed: true}}
  end

  def handle_info({:check, check_id}, state) do
    run_check(check_id, state)
    {:noreply, state}
  end

  def handle_info(%Event{topic: topic} = event, state) do
    state = dispatch_to_hook(event, state)

    case check_completion(topic, event, state) do
      :complete ->
        state = %{state | status: :completed}
        run_cleanup(state)
        {:stop, :normal, state}

      :continue ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:command, name, args}, state) do
    case get_in(state.config, [Access.key(:commands), name]) do
      nil ->
        {:noreply, state}

      fun ->
        case apply(fun, [state | args]) do
          {:noreply, new_state} -> {:noreply, new_state}
          new_state when is_map(new_state) -> {:noreply, new_state}
          _ -> {:noreply, state}
        end
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    reply = %{
      run_id: state.run_id,
      kind: state.kind,
      session: state.session,
      deadline_passed: state.deadline_passed,
      started_at: state.started_at,
      status: state.status,
      runtime: state.runtime
    }

    {:reply, reply, state}
  end

  def handle_call(:deadline_passed?, _from, state) do
    {:reply, state.deadline_passed, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Single emission point for :run_complete. Only fires for completed runs.
    # OTP guarantees terminate/2 runs after {:stop, :normal}, so this covers
    # both the happy path and crashes during run_cleanup.
    if state.status == :completed do
      Events.emit(Event.new("fleet.run.complete", state.run_id, run_complete_payload(state)))
    end

    emit_signal(state.config.signals.terminated, build_terminate_payload(state))

    Events.emit(
      Event.new(
        "fleet.run.terminated",
        state.run_id,
        %{kind: state.kind, run_id: state.run_id, session: state.session}
      )
    )

    :ok
  end

  # ---------------------------------------------------------------------------
  # Mode configuration — delegates to Runner.Modes
  # ---------------------------------------------------------------------------

  defp runner_hooks do
    %{
      mes_on_init: &mes_on_init/1,
      mes_on_signal: &mes_on_signal/2,
      pipeline_check_stale: &pipeline_check_stale/1,
      pipeline_check_health: &pipeline_check_health/1,
      pipeline_sync_task: &pipeline_sync_task/2,
      pipeline_on_complete: &pipeline_on_complete/1
    }
  end

  # ---------------------------------------------------------------------------
  # MES hook implementations (replaces Runner.Hooks.MES)
  # ---------------------------------------------------------------------------

  defp mes_on_init(state) do
    team_name =
      get_in(state.config, [Access.key(:hooks), Access.key(:team_name)]) || state.session

    research_context = %{
      open_gaps: ResearchContext.open_gaps(),
      existing_plugins: ResearchContext.existing_plugins(),
      dead_zones: ResearchContext.dead_zones(),
      pain_points: ResearchContext.pain_points()
    }

    spec =
      TeamSpec.build(:mes, state.run_id, team_name, research_context: research_context)

    case mes_team_launch().launch(spec) do
      {:ok, _session} ->
        :ok

      {:error, reason} ->
        Events.emit(
          Event.new(
            "mes.cycle.failed",
            state.run_id,
            %{run_id: state.run_id, reason: inspect(reason)}
          )
        )
    end

    :ok
  end

  defp mes_on_signal(
         %Event{topic: "mes.quality_gate.failed", data: %{run_id: run_id} = data},
         %{run_id: run_id} = state
       ) do
    failures = Map.get(state.runtime, :gate_failures, 0) + 1
    mes_spawn_corrective_agent(state.run_id, state.session, data[:reason], failures)
    put_in(state.runtime[:gate_failures], failures)
  end

  defp mes_on_signal(
         %Event{topic: "mes.quality_gate.escalated", data: %{run_id: run_id}},
         %{run_id: run_id} = state
       ) do
    %{state | deadline_passed: true}
  end

  defp mes_on_signal(_event, state), do: state

  defp mes_spawn_corrective_agent(run_id, session, reason, attempt) do
    spec =
      TeamSpec.build_corrective(run_id, session, reason, attempt,
        prompt_module: Ichor.Workshop.TeamPrompts
      )

    case mes_team_launch().launch_into_existing_session(spec, session) do
      :ok ->
        Events.emit(
          Event.new(
            "mes.corrective_agent.spawned",
            run_id,
            %{run_id: run_id, session: session, attempt: attempt}
          )
        )

      {:error, err} ->
        Events.emit(
          Event.new(
            "mes.corrective_agent.failed",
            run_id,
            %{run_id: run_id, session: session, reason: inspect(err)}
          )
        )
    end
  end

  defp mes_team_launch do
    Application.get_env(:ichor, :mes_team_launch_module, TeamLaunch)
  end

  # ---------------------------------------------------------------------------
  # Pipeline hook implementations
  # ---------------------------------------------------------------------------

  defp pipeline_check_stale(state) do
    with {:ok, pipeline_tasks} <- PipelineTask.by_run(state.run_id) do
      now = DateTime.utc_now()

      pipeline_tasks
      |> Enum.filter(&(to_string(&1.status) == "in_progress" and pipeline_stale?(&1, now)))
      |> Enum.each(&PipelineTask.reset/1)
    end

    :ok
  end

  defp pipeline_check_health(state) do
    with {:ok, pipeline_tasks} <- PipelineTask.by_run(state.run_id) do
      nodes = Enum.map(pipeline_tasks, &PipelineGraph.to_graph_node/1)
      issues = HealthChecker.health_issues(nodes, DateTime.utc_now())

      Events.emit(
        Event.new(
          "pipeline.health_report",
          state.run_id,
          %{run_id: state.run_id, healthy: issues == [], issue_count: length(issues)}
        )
      )
    end

    :ok
  end

  defp pipeline_sync_task(state, task) do
    Task.start(fn -> Exporter.sync_task_to_file(task, state.project_path) end)
    {:noreply, state}
  end

  defp pipeline_on_complete(state) do
    with {:ok, pipeline} when pipeline.status != :completed <- Pipeline.get(state.run_id) do
      Pipeline.complete(pipeline)
    end

    :ok
  end

  defp pipeline_stale?(%{updated_at: nil}, _now), do: true

  defp pipeline_stale?(%{updated_at: ts}, now) do
    DateTime.diff(now, ts, :minute) > @stale_threshold_min
  end

  # ---------------------------------------------------------------------------
  # Cleanup dispatch (replaces Runner.Hooks)
  # ---------------------------------------------------------------------------

  defp do_cleanup(:signal, _state), do: :ok
  defp do_cleanup(:teardown, %{team_spec: nil}), do: :ok

  defp do_cleanup(:teardown, state) do
    TeamLaunch.teardown(state.team_spec)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Core GenServer helpers
  # ---------------------------------------------------------------------------

  defp session_for(:mes, run_id, _opts), do: RunRef.session_name(RunRef.new(:mes, run_id))

  defp session_for(_kind, _run_id, opts) do
    case Keyword.get(opts, :team_spec) do
      nil -> Keyword.get(opts, :session, "")
      spec -> spec.session
    end
  end

  defp schedule_timers(timers, state) do
    schedule_liveness(timers)

    case Map.get(timers, :deadline_ms) do
      nil -> :ok
      deadline_ms -> Process.send_after(self(), :deadline, deadline_ms)
    end

    case Map.get(timers, :on_init) do
      nil -> :ok
      init_fn -> init_fn.(state)
    end
  end

  defp schedule_liveness(nil), do: :ok

  defp schedule_liveness(timers) do
    case Map.get(timers, :liveness_ms) do
      nil -> :ok
      ms -> Process.send_after(self(), :check_liveness, ms)
    end
  end

  defp schedule_checks(nil), do: :ok

  defp schedule_checks(checks) do
    Enum.each(checks, fn %{id: id, every_ms: ms} ->
      Process.send_after(self(), {:check, id}, ms)
    end)
  end

  defp run_check(check_id, state) do
    checks = state.config.checks || []

    case Enum.find(checks, fn c -> c.id == check_id end) do
      nil ->
        :ok

      %{callback: fun, every_ms: ms} ->
        fun.(state)
        Process.send_after(self(), {:check, check_id}, ms)
    end
  end

  defp tmux_available?(session) do
    mod = Application.get_env(:ichor, :tmux_launcher_module, TmuxLauncher)
    mod.available?(session)
  end

  defp run_cleanup(state) do
    policy = state.config.cleanup.policy
    do_cleanup(policy, state)
  end

  defp run_complete_payload(state) do
    %{kind: state.kind, run_id: state.run_id, session: state.session}
  end

  defp dispatch_to_hook(msg, state) do
    case get_in(state.config, [Access.key(:hooks), Access.key(:on_signal)]) do
      nil -> state
      fun -> fun.(msg, state)
    end
  end

  defp check_completion(topic, event, state) do
    case state.config.completion do
      nil ->
        :continue

      %{source: :signal, signal: signal} ->
        if topic == signal_to_topic(signal),
          do: maybe_complete_on_signal(event, state),
          else: :continue

      %{source: :signal_or_message, signal: signal} ->
        cond do
          topic == signal_to_topic(signal) -> maybe_complete_on_signal(event, state)
          topic == "messages.delivered" -> maybe_complete_on_message(event, state)
          true -> :continue
        end

      %{source: :message_delivered} ->
        if topic == "messages.delivered",
          do: maybe_complete_on_message(event, state),
          else: :continue

      _ ->
        :continue
    end
  end

  defp maybe_complete_on_signal(%Event{data: %{run_id: run_id}}, %{run_id: run_id} = state) do
    on_complete = get_in(state.config, [Access.key(:hooks), Access.key(:on_complete)])
    if on_complete, do: on_complete.(state)
    :complete
  end

  defp maybe_complete_on_signal(_event, _state), do: :continue

  defp maybe_complete_on_message(
         %Event{data: %{msg_map: %{to: "operator", from: from}}},
         state
       )
       when is_binary(from) do
    completion = state.config.completion
    coordinator_id = Map.get(completion, :coordinator_id_fn, &default_coordinator_id/1).(state)

    case from_coordinator?(from, coordinator_id) do
      true ->
        on_complete = get_in(state.config, [Access.key(:hooks), Access.key(:on_complete)])
        if on_complete, do: on_complete.(state)
        :complete

      false ->
        :continue
    end
  end

  defp maybe_complete_on_message(_event, _state), do: :continue

  defp from_coordinator?(from, coordinator_id),
    do: from == coordinator_id or String.starts_with?(from, coordinator_id)

  defp default_coordinator_id(%{session: session}), do: "#{session}-coordinator"

  defp emit_signal(nil, _payload), do: :ok

  defp emit_signal(signal, payload) do
    clean = Map.reject(payload, fn {_k, v} -> is_nil(v) end)
    key = Map.get(clean, :run_id)

    Events.emit(
      Event.new(
        signal_to_topic(signal),
        key,
        clean
      )
    )
  end

  # Maps mode signal atoms to topic strings for emit_signal/2.
  # These are internal lifecycle signals defined in Runner.Mode structs.
  @signal_topic_map %{
    mes_run_started: "mes.run.started",
    mes_tmux_gone: "mes.tmux.gone",
    mes_run_terminated: "mes.run.terminated",
    mes_deadline_reached: "mes.deadline.reached",
    planning_run_init: "planning.run.init",
    planning_run_complete: "planning.run.complete",
    planning_tmux_gone: "planning.tmux.gone",
    planning_run_terminated: "planning.run.terminated",
    pipeline_ready: "pipeline.ready",
    pipeline_completed: "pipeline.completed",
    pipeline_tmux_gone: "pipeline.tmux.gone",
    pipeline_terminated: "pipeline.terminated",
    run_complete: "fleet.run.complete"
  }

  defp signal_to_topic(signal) when is_atom(signal) do
    Map.get(@signal_topic_map, signal, Atom.to_string(signal) |> String.replace("_", "."))
  end

  defp build_terminate_payload(%{kind: :mes} = state) do
    %{run_id: state.run_id}
  end

  defp build_terminate_payload(%{kind: :planning, runtime: %{mode: mode}} = state) do
    %{run_id: state.run_id, mode: mode}
  end

  defp build_terminate_payload(%{kind: :planning} = state) do
    %{run_id: state.run_id, mode: nil}
  end

  defp build_terminate_payload(%{kind: :pipeline} = state) do
    %{run_id: state.run_id, session: state.session}
  end
end
