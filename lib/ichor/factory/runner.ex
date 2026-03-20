defmodule Ichor.Factory.Runner do
  @moduledoc """
  Unified GenServer representing a single run lifecycle.

  Replaces the former BuildRunner (MES), PlanRunner (Planning), and pipeline
  runner with a single data-driven implementation. Behavioral differences are
  expressed through `%Runner.Mode{}` config structs and hook functions.

  Registry keys by kind:
    - :mes     -> {:run, run_id}
    - :planning -> {:planning_run, run_id}
    - :pipeline -> {:pipeline_run, run_id}
  """

  use GenServer, restart: :temporary

  alias Ichor.Factory.{Graph, Pipeline, PipelineTask}
  alias Ichor.Factory.Workers.RunCleanupWorker
  alias Ichor.Infrastructure.{TeamLaunch, TmuxLauncher}
  alias Ichor.Signals
  alias Ichor.Signals.Message
  alias Ichor.Workshop.TeamSpec

  @liveness_ms :timer.seconds(30)
  @liveness_pipeline_ms :timer.seconds(60)
  @deadline_ms :timer.minutes(10)
  @stale_check_ms :timer.seconds(60)
  @health_check_ms :timer.seconds(30)
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
      # %{policy: :teardown | :mes_janitor}
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
    @moduledoc "Runtime state for a unified Runner process."

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
  def via(kind, run_id), do: {:via, Registry, {Ichor.Registry, {registry_key(kind), run_id}}}

  @doc "Returns the pid for the given kind and run_id if alive, or nil."
  @spec lookup(:mes | :planning | :pipeline, String.t()) :: pid() | nil
  def lookup(kind, run_id) do
    case Registry.lookup(Ichor.Registry, {registry_key(kind), run_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Lists all active run IDs and PIDs for the given kind."
  @spec list_all(:mes | :planning | :pipeline) :: [{String.t(), pid()}]
  def list_all(kind) do
    key = registry_key(kind)

    Registry.select(Ichor.Registry, [
      {{{key, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc "Starts a new Runner under the appropriate DynamicSupervisor."
  @spec start(:mes | :planning | :pipeline, keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start(kind, opts) do
    supervisor = supervisor_for(kind)
    DynamicSupervisor.start_child(supervisor, {__MODULE__, [kind: kind] ++ opts})
  end

  @doc "Enqueues a write-through sync task. Pipeline-kind only."
  @spec sync_task(String.t(), struct() | map()) :: :ok
  def sync_task(run_id, task),
    do: GenServer.cast(via(:pipeline, run_id), {:command, :sync_task, [task]})

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
    config = build_mode_config(kind, run_id, opts)

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

    subscribe_all(config.subscriptions)
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

  def handle_info(%Message{name: name} = msg, state) do
    state = dispatch_to_hook(msg, state)

    case check_completion(name, msg, state) do
      :complete ->
        run_cleanup(state)
        {:stop, :normal, state}

      :continue ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:command, name, args}, state) do
    case get_in(state.config, [Access.key(:commands), name]) do
      nil -> {:noreply, state}
      fun -> apply(fun, [state | args])
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
    signal = state.config.signals.terminated

    emit_signal(signal, build_terminate_payload(state))
    maybe_enqueue_cleanup(state, "terminate")
    :ok
  end

  # ---------------------------------------------------------------------------
  # Mode configuration (replaces Runner.Modes)
  # ---------------------------------------------------------------------------

  defp build_mode_config(:mes, run_id, opts) do
    team_name = Keyword.get(opts, :team_name, "mes-#{run_id}")

    %Mode{
      kind: :mes,
      subscriptions: [:mes],
      timers: %{
        liveness_ms: @liveness_ms,
        deadline_ms: @deadline_ms,
        on_init: &mes_on_init/1
      },
      completion: %{
        source: :signal,
        signal: :mes_project_created
      },
      checks: nil,
      cleanup: %{policy: :mes_janitor},
      signals: %{
        ready: :mes_run_started,
        completed: :mes_run_complete,
        tmux_gone: :mes_tmux_gone,
        terminated: :mes_run_terminated,
        deadline_reached: :mes_deadline_reached
      },
      commands: nil,
      hooks: %{
        on_signal: &mes_on_signal/2,
        on_complete: fn state ->
          Signals.emit(:mes_run_complete, %{
            run_id: state.run_id,
            session: state.session
          })
        end,
        team_name: team_name
      }
    }
  end

  defp build_mode_config(:planning, _run_id, opts) do
    mode_label = Keyword.get(opts, :mode, "unknown")

    %Mode{
      kind: :planning,
      subscriptions: [:messages],
      timers: %{liveness_ms: @liveness_ms},
      completion: %{
        source: :message_delivered,
        coordinator_id_fn: &planning_coordinator_id/1
      },
      checks: nil,
      cleanup: %{policy: :teardown},
      signals: %{
        ready: :planning_run_init,
        completed: :planning_run_complete,
        tmux_gone: :planning_tmux_gone,
        terminated: :planning_run_terminated
      },
      commands: nil,
      hooks: %{
        on_complete: fn state ->
          Signals.emit(:planning_run_complete, %{
            run_id: state.run_id,
            mode: mode_label,
            session: state.session,
            delivered_by: "operator"
          })
        end
      }
    }
  end

  defp build_mode_config(:pipeline, _run_id, _opts) do
    %Mode{
      kind: :pipeline,
      subscriptions: [:messages],
      timers: %{liveness_ms: @liveness_pipeline_ms},
      completion: %{
        source: :message_delivered,
        coordinator_id_fn: &pipeline_coordinator_id/1
      },
      checks: [
        %{id: :stale, every_ms: @stale_check_ms, callback: &pipeline_check_stale/1},
        %{id: :health, every_ms: @health_check_ms, callback: &pipeline_check_health/1}
      ],
      cleanup: %{policy: :teardown},
      signals: %{
        ready: :pipeline_ready,
        completed: :pipeline_completed,
        tmux_gone: :pipeline_tmux_gone,
        terminated: :pipeline_terminated
      },
      commands: %{
        sync_task: &pipeline_sync_task/2
      },
      hooks: %{
        on_complete: &pipeline_on_complete/1
      }
    }
  end

  defp planning_coordinator_id(%{session: session}), do: session
  defp pipeline_coordinator_id(%{session: session}), do: "#{session}-coordinator"

  # ---------------------------------------------------------------------------
  # MES hook implementations (replaces Runner.Hooks.MES)
  # ---------------------------------------------------------------------------

  defp mes_on_init(state) do
    team_name =
      get_in(state.config, [Access.key(:hooks), Access.key(:team_name)]) || state.session

    spec = TeamSpec.build(:mes, state.run_id, team_name)

    case mes_team_launch().launch(spec) do
      {:ok, _session} ->
        :ok

      {:error, reason} ->
        Signals.emit(:mes_cycle_failed, %{run_id: state.run_id, reason: inspect(reason)})
    end

    :ok
  end

  defp mes_on_signal(
         %Message{name: :mes_quality_gate_failed, data: %{run_id: run_id} = data},
         %{run_id: run_id} = state
       ) do
    failures = Map.get(state.runtime, :gate_failures, 0) + 1
    mes_spawn_corrective_agent(state.run_id, state.session, data[:reason], failures)
    put_in(state.runtime[:gate_failures], failures)
  end

  defp mes_on_signal(
         %Message{name: :mes_quality_gate_escalated, data: %{run_id: run_id}},
         %{run_id: run_id} = state
       ) do
    %{state | deadline_passed: true}
  end

  defp mes_on_signal(_msg, state), do: state

  defp mes_spawn_corrective_agent(run_id, session, reason, attempt) do
    spec = TeamSpec.build_corrective(run_id, session, reason, attempt)

    case mes_team_launch().launch_into_existing_session(spec, session) do
      :ok ->
        Signals.emit(:mes_corrective_agent_spawned, %{
          run_id: run_id,
          session: session,
          attempt: attempt
        })

      {:error, err} ->
        Signals.emit(:mes_corrective_agent_failed, %{
          run_id: run_id,
          session: session,
          reason: inspect(err)
        })
    end
  end

  defp mes_cleanup(state) do
    enqueue_mes_cleanup(state, "completed")
    :ok
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
      nodes = Enum.map(pipeline_tasks, &Graph.to_graph_node/1)
      issues = health_issues(nodes, DateTime.utc_now())

      Signals.emit(:pipeline_health_report, %{
        run_id: state.run_id,
        healthy: issues == [],
        issue_count: length(issues)
      })
    end

    :ok
  end

  defp pipeline_sync_task(state, task) do
    Task.start(fn -> sync_task_to_file(task, state.project_path) end)
    {:noreply, state}
  end

  defp pipeline_on_complete(state) do
    with {:ok, pipeline} <- Pipeline.get(state.run_id) do
      Pipeline.complete(pipeline)
      Signals.emit(:pipeline_completed, %{run_id: state.run_id, label: pipeline.label})
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

  defp do_cleanup(:mes_janitor, state), do: mes_cleanup(state)
  defp do_cleanup(:teardown, %{team_spec: nil}), do: :ok

  defp do_cleanup(:teardown, state) do
    TeamLaunch.teardown(state.team_spec)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Core GenServer helpers
  # ---------------------------------------------------------------------------

  defp registry_key(:mes), do: :run
  defp registry_key(:planning), do: :planning_run
  defp registry_key(:pipeline), do: :pipeline_run

  defp supervisor_for(:mes), do: Ichor.Factory.BuildRunSupervisor
  defp supervisor_for(:planning), do: Ichor.Factory.PlanRunSupervisor
  defp supervisor_for(:pipeline), do: Ichor.Factory.DynRunSupervisor

  defp session_for(:mes, run_id, _opts), do: "mes-#{run_id}"

  defp session_for(_kind, _run_id, opts) do
    case Keyword.get(opts, :team_spec) do
      nil -> Keyword.get(opts, :session, "")
      spec -> spec.session
    end
  end

  defp subscribe_all(subscriptions) do
    Enum.each(subscriptions, &Signals.subscribe/1)
  end

  defp schedule_timers(timers, state) do
    if is_map(timers) do
      schedule_liveness(timers)

      if deadline_ms = Map.get(timers, :deadline_ms) do
        Process.send_after(self(), :deadline, deadline_ms)
      end

      if init_fn = Map.get(timers, :on_init) do
        init_fn.(state)
      end
    end
  end

  defp schedule_liveness(nil), do: :ok

  defp schedule_liveness(timers) do
    if ms = Map.get(timers, :liveness_ms) do
      Process.send_after(self(), :check_liveness, ms)
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

  defp maybe_enqueue_cleanup(%{kind: :mes} = state, trigger),
    do: enqueue_mes_cleanup(state, trigger)

  defp maybe_enqueue_cleanup(_state, _trigger), do: :ok

  defp enqueue_mes_cleanup(state, trigger) do
    case RunCleanupWorker.enqueue(state.run_id, trigger: trigger) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Signals.emit(:mes_janitor_error, %{run_id: state.run_id, reason: inspect(reason)})
        :ok
    end
  end

  defp dispatch_to_hook(msg, state) do
    case get_in(state.config, [Access.key(:hooks), Access.key(:on_signal)]) do
      nil -> state
      fun -> fun.(msg, state)
    end
  end

  defp check_completion(name, msg, state) do
    case state.config.completion do
      nil ->
        :continue

      %{source: :signal, signal: signal} when name == signal ->
        maybe_complete_on_signal(msg, state)

      %{source: :message_delivered} when name == :message_delivered ->
        maybe_complete_on_message(msg, state)

      _ ->
        :continue
    end
  end

  defp maybe_complete_on_signal(%Message{data: %{run_id: run_id}}, %{run_id: run_id} = state) do
    on_complete = get_in(state.config, [Access.key(:hooks), Access.key(:on_complete)])
    if on_complete, do: on_complete.(state)
    :complete
  end

  defp maybe_complete_on_signal(_msg, _state), do: :continue

  defp maybe_complete_on_message(
         %Message{data: %{msg_map: %{to: "operator", from: from}}},
         state
       )
       when is_binary(from) do
    completion = state.config.completion
    coordinator_id = Map.get(completion, :coordinator_id_fn, &default_coordinator_id/1).(state)

    if from == coordinator_id or String.starts_with?(from, coordinator_id) do
      on_complete = get_in(state.config, [Access.key(:hooks), Access.key(:on_complete)])
      if on_complete, do: on_complete.(state)
      :complete
    else
      :continue
    end
  end

  defp maybe_complete_on_message(_msg, _state), do: :continue

  defp default_coordinator_id(%{session: session}), do: "#{session}-coordinator"

  defp emit_signal(nil, _payload), do: :ok

  defp emit_signal(signal, payload) do
    Signals.emit(signal, Map.reject(payload, fn {_k, v} -> is_nil(v) end))
  end

  defp build_terminate_payload(%{kind: :mes} = state) do
    %{run_id: state.run_id}
  end

  defp build_terminate_payload(%{kind: :planning} = state) do
    %{run_id: state.run_id, mode: Map.get(state.runtime, :mode)}
  end

  defp build_terminate_payload(%{kind: :pipeline} = state) do
    %{run_id: state.run_id, session: state.session}
  end

  # ---------------------------------------------------------------------------
  # HealthChecker (formerly Ichor.Projects.HealthChecker)
  # ---------------------------------------------------------------------------

  @stale_threshold_min 10

  defp health_issues(nodes, now) do
    stale_health_issues(nodes, now) ++
      conflict_health_issues(nodes) ++
      deadlock_health_issues(nodes) ++
      orphan_health_issues(nodes)
  end

  defp stale_health_issues(nodes, now) do
    nodes
    |> Graph.stale_items(now, @stale_threshold_min)
    |> Enum.map(fn node ->
      %{
        type: :stale_in_progress,
        severity: :warning,
        external_id: node.id,
        description:
          "Task execution #{node.id} has been in_progress for over #{@stale_threshold_min} minutes"
      }
    end)
  end

  defp conflict_health_issues(nodes) do
    nodes
    |> Graph.file_conflicts()
    |> Enum.map(fn {a, b, files} ->
      %{
        type: :file_conflict,
        severity: :error,
        external_id: "#{a}+#{b}",
        description: "Tasks #{a} and #{b} share files: #{Enum.join(files, ", ")}"
      }
    end)
  end

  defp deadlock_health_issues(nodes) do
    failed = nodes |> Enum.filter(&(to_string(&1.status) == "failed")) |> MapSet.new(& &1.id)

    nodes
    |> Enum.filter(fn node ->
      to_string(node.status) == "pending" and
        Enum.any?(node.blocked_by, &MapSet.member?(failed, &1))
    end)
    |> Enum.map(fn node ->
      %{
        type: :deadlocked,
        severity: :error,
        external_id: node.id,
        description:
          "Pipeline task #{node.id} is blocked by failed dependency tasks: #{Enum.join(node.blocked_by, ", ")}"
      }
    end)
  end

  defp orphan_health_issues(nodes) do
    failed = nodes |> Enum.filter(&(to_string(&1.status) == "failed")) |> MapSet.new(& &1.id)

    nodes
    |> Enum.filter(fn node ->
      to_string(node.status) == "pending" and
        node.blocked_by != [] and
        Enum.all?(node.blocked_by, &MapSet.member?(failed, &1))
    end)
    |> Enum.map(fn node ->
      %{
        type: :orphaned,
        severity: :warning,
        external_id: node.id,
        description: "Pipeline task #{node.id} is pending but all blockers have failed"
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Exporter (formerly Ichor.Projects.Exporter)
  # ---------------------------------------------------------------------------

  defp sync_task_to_file(_task, nil), do: :ok
  defp sync_task_to_file(_task, ""), do: :ok

  defp sync_task_to_file(task, project_path) do
    tasks_path = Path.join(project_path, "tasks.jsonl")
    jq_update_item(tasks_path, task.external_id, to_string(task.status), task.owner || "")
  end

  defp jq_update_item(path, external_id, new_status, new_owner) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    jq_expr =
      ~s(if .id == $eid then .status = $st | .owner = $ow | .updated = $ts else . end)

    jq_in_place(path, jq_expr, [
      "--arg",
      "eid",
      external_id,
      "--arg",
      "st",
      new_status,
      "--arg",
      "ow",
      new_owner,
      "--arg",
      "ts",
      now
    ])
  end

  defp jq_in_place(path, expr, extra_args) do
    tmp = path <> ".pipeline_tmp"

    case System.cmd("jq", ["-c"] ++ extra_args ++ [expr, path], stderr_to_stdout: true) do
      {output, 0} ->
        case File.write(tmp, output) do
          :ok ->
            File.rename!(tmp, path)
            :ok

          err ->
            File.rm(tmp)
            err
        end

      {err, _} ->
        {:error, err}
    end
  end
end
