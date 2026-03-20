defmodule Ichor.Projects.Runner do
  @moduledoc """
  Unified GenServer representing a single run lifecycle.

  Replaces BuildRunner (MES), PlanRunner (Genesis), and RunProcess (DAG)
  with a single data-driven implementation. Behavior differences are
  expressed through `%Runner.Mode{}` config structs and hook functions.

  Registry keys by kind:
    - :mes     -> {:run, run_id}
    - :genesis -> {:genesis_run, run_id}
    - :dag     -> {:dag_run, run_id}

  All three runner kinds are still running their original modules.
  This module is built alongside the originals; callers migrate in a
  subsequent phase.
  """

  use GenServer, restart: :temporary

  alias Ichor.Control.Lifecycle.{TeamLaunch, TmuxLauncher}
  alias Ichor.Projects.{Exporter, HealthChecker, Janitor, Job, Run, RuntimeSignals}
  alias Ichor.Projects.{TeamCleanup, TeamSpecBuilder}
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @liveness_ms :timer.seconds(30)
  @liveness_dag_ms :timer.seconds(60)
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
      # %{sync_job: fun | nil}
      :commands,
      # %{on_signal: fun | nil, on_complete: fun | nil}
      :hooks
    ]

    @type t :: %__MODULE__{
            kind: :mes | :genesis | :dag,
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
      :node_id,
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
            kind: :mes | :genesis | :dag,
            session: String.t(),
            team_spec: struct() | nil,
            node_id: String.t() | nil,
            project_path: String.t() | nil,
            config: Ichor.Projects.Runner.Mode.t(),
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
  @spec via(:mes | :genesis | :dag, String.t()) ::
          {:via, Registry, {Ichor.Registry, {atom(), String.t()}}}
  def via(kind, run_id), do: {:via, Registry, {Ichor.Registry, {registry_key(kind), run_id}}}

  @doc "Returns the pid for the given kind and run_id if alive, or nil."
  @spec lookup(:mes | :genesis | :dag, String.t()) :: pid() | nil
  def lookup(kind, run_id) do
    case Registry.lookup(Ichor.Registry, {registry_key(kind), run_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Lists all active run IDs and PIDs for the given kind."
  @spec list_all(:mes | :genesis | :dag) :: [{String.t(), pid()}]
  def list_all(kind) do
    key = registry_key(kind)

    Registry.select(Ichor.Registry, [
      {{{key, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc "Starts a new Runner under the appropriate DynamicSupervisor."
  @spec start(:mes | :genesis | :dag, keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start(kind, opts) do
    supervisor = supervisor_for(kind)
    DynamicSupervisor.start_child(supervisor, {__MODULE__, [kind: kind] ++ opts})
  end

  @doc "Enqueues a write-through sync job. DAG-kind only."
  @spec sync_job(String.t(), struct() | map()) :: :ok
  def sync_job(run_id, job), do: GenServer.cast(via(:dag, run_id), {:command, :sync_job, [job]})

  @doc "Returns a status map for the given kind and run_id."
  @spec status(:mes | :genesis | :dag, String.t()) :: map() | nil
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
      node_id: Keyword.get(opts, :node_id),
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

  defp build_mode_config(:genesis, _run_id, opts) do
    mode_label = Keyword.get(opts, :mode, "unknown")

    %Mode{
      kind: :genesis,
      subscriptions: [:messages],
      timers: %{liveness_ms: @liveness_ms},
      completion: %{
        source: :message_delivered,
        coordinator_id_fn: &genesis_coordinator_id/1
      },
      checks: nil,
      cleanup: %{policy: :teardown},
      signals: %{
        ready: :genesis_run_init,
        completed: :genesis_run_complete,
        tmux_gone: :genesis_tmux_gone,
        terminated: :genesis_run_terminated
      },
      commands: nil,
      hooks: %{
        on_complete: fn state ->
          Signals.emit(:genesis_run_complete, %{
            run_id: state.run_id,
            mode: mode_label,
            session: state.session,
            delivered_by: "operator"
          })
        end
      }
    }
  end

  defp build_mode_config(:dag, _run_id, _opts) do
    %Mode{
      kind: :dag,
      subscriptions: [:messages],
      timers: %{liveness_ms: @liveness_dag_ms},
      completion: %{
        source: :message_delivered,
        coordinator_id_fn: &dag_coordinator_id/1
      },
      checks: [
        %{id: :stale, every_ms: @stale_check_ms, callback: &dag_check_stale/1},
        %{id: :health, every_ms: @health_check_ms, callback: &dag_check_health/1}
      ],
      cleanup: %{policy: :teardown},
      signals: %{
        ready: :dag_run_ready,
        completed: :dag_run_completed,
        tmux_gone: :dag_tmux_gone,
        terminated: :dag_run_terminated
      },
      commands: %{
        sync_job: &dag_sync_job/2
      },
      hooks: %{
        on_complete: &dag_on_complete/1
      }
    }
  end

  defp genesis_coordinator_id(%{session: session}), do: session
  defp dag_coordinator_id(%{session: session}), do: "#{session}-coordinator"

  # ---------------------------------------------------------------------------
  # MES hook implementations (replaces Runner.Hooks.MES)
  # ---------------------------------------------------------------------------

  defp mes_on_init(state) do
    pid = self()

    team_name =
      get_in(state.config, [Access.key(:hooks), Access.key(:team_name)]) || state.session

    spec = mes_team_spec_builder().build_team_spec(state.run_id, team_name)

    case mes_team_launch().launch(spec) do
      {:ok, _session} ->
        :ok

      {:error, reason} ->
        Signals.emit(:mes_cycle_failed, %{run_id: state.run_id, reason: inspect(reason)})
    end

    Janitor.monitor_run(state.run_id, pid)
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
    builder = mes_team_spec_builder()
    spec = builder.build_corrective_team_spec(run_id, session, reason, attempt)

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
    mes_team_cleanup().kill_session(state.session)
    :ok
  end

  defp mes_team_spec_builder do
    Application.get_env(:ichor, :mes_team_spec_builder_module, TeamSpecBuilder)
  end

  defp mes_team_launch do
    Application.get_env(:ichor, :mes_team_launch_module, TeamLaunch)
  end

  defp mes_team_cleanup do
    Application.get_env(:ichor, :mes_team_cleanup_module, TeamCleanup)
  end

  # ---------------------------------------------------------------------------
  # DAG hook implementations (replaces Runner.Hooks.DAG)
  # ---------------------------------------------------------------------------

  defp dag_check_stale(state) do
    with {:ok, jobs} <- Job.by_run(state.run_id) do
      now = DateTime.utc_now()

      jobs
      |> Enum.filter(&(to_string(&1.status) == "in_progress" and dag_stale?(&1, now)))
      |> Enum.each(&Job.reset/1)
    end

    :ok
  end

  defp dag_check_health(state) do
    case HealthChecker.check(state.run_id) do
      {:ok, report} ->
        RuntimeSignals.emit_health_report(state.run_id, report.healthy, length(report.issues))

      _ ->
        :ok
    end

    :ok
  end

  defp dag_sync_job(state, job) do
    Task.start(fn -> Exporter.sync_to_file(job, state.project_path) end)
    {:noreply, state}
  end

  defp dag_on_complete(state) do
    with {:ok, run} <- Run.get(state.run_id) do
      Run.complete(run)
      RuntimeSignals.emit_run_completed(state.run_id, run.label)
    end

    :ok
  end

  defp dag_stale?(%{updated_at: nil}, _now), do: true

  defp dag_stale?(%{updated_at: ts}, now) do
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
  defp registry_key(:genesis), do: :genesis_run
  defp registry_key(:dag), do: :dag_run

  defp supervisor_for(:mes), do: Ichor.Projects.BuildRunSupervisor
  defp supervisor_for(:genesis), do: Ichor.Projects.PlanRunSupervisor
  defp supervisor_for(:dag), do: Ichor.Projects.DynRunSupervisor

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

  defp build_terminate_payload(%{kind: :genesis} = state) do
    %{run_id: state.run_id, mode: Map.get(state.runtime, :mode)}
  end

  defp build_terminate_payload(%{kind: :dag} = state) do
    %{run_id: state.run_id, session: state.session}
  end
end
