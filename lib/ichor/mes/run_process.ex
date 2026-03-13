defmodule Ichor.Mes.RunProcess do
  @moduledoc """
  GenServer representing a single MES manufacturing run.

  Manages the lifecycle of one 5-agent team:
    1. Creates tmux session with agent windows
    2. Registers agents in BEAM fleet
    3. Periodically checks if the tmux session is still alive
    4. Cleans up on termination (disband team + kill tmux + prompt files)

  The RunProcess stays alive as long as the tmux session exists,
  keeping BEAM agent registrations intact for dashboard messaging.
  After the brief deadline (10 min), it stops the Scheduler from
  counting this run as "active" but does NOT kill the tmux session.
  Cleanup only happens when all tmux windows are gone.

  Registered in Ichor.Registry via `{:run, run_id}`.
  Supervised under Ichor.Mes.RunSupervisor (DynamicSupervisor).
  """

  use GenServer, restart: :temporary

  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Mes.TeamSpawner
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @deadline_ms :timer.minutes(10)
  @liveness_interval_ms :timer.seconds(30)

  defstruct [:run_id, :team_name, :session, :deadline_passed, agents: [], gate_failures: 0]

  # ── Public API ──────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(run_id))
  end

  @spec via(String.t()) :: {:via, Registry, {Ichor.Registry, {:run, String.t()}}}
  def via(run_id), do: {:via, Registry, {Ichor.Registry, {:run, run_id}}}

  @spec lookup(String.t()) :: pid() | nil
  def lookup(run_id) do
    case Registry.lookup(Ichor.Registry, {:run, run_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @spec list_all() :: [{String.t(), pid()}]
  def list_all do
    Registry.select(Ichor.Registry, [
      {{{:run, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc "Returns only runs that haven't passed their deadline (for Scheduler concurrency limit)."
  @spec list_active() :: [{String.t(), pid()}]
  def list_active do
    list_all()
    |> Enum.filter(fn {_run_id, pid} ->
      try do
        not GenServer.call(pid, :deadline_passed?, 1_000)
      catch
        :exit, _ -> false
      end
    end)
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    team_name = Keyword.fetch!(opts, :team_name)

    state = %__MODULE__{
      run_id: run_id,
      team_name: team_name,
      session: "mes-#{run_id}",
      deadline_passed: false
    }

    Signals.subscribe(:mes)
    Signals.emit(:mes_run_init, %{run_id: run_id, team_name: team_name})
    {:ok, state, {:continue, :spawn_team}}
  end

  @impl true
  def handle_continue(:spawn_team, state) do
    case TeamSpawner.spawn_run(state.run_id, state.team_name) do
      {:ok, session} ->
        Ichor.Mes.Janitor.monitor_run(state.run_id, self())
        Process.send_after(self(), :deadline, @deadline_ms)
        schedule_liveness_check()
        Signals.emit(:mes_run_started, %{run_id: state.run_id, session: session})
        {:noreply, %{state | session: session}}

      {:error, reason} ->
        Signals.emit(:mes_cycle_failed, %{run_id: state.run_id, reason: inspect(reason)})
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_call(:deadline_passed?, _from, state) do
    {:reply, Map.get(state, :deadline_passed, false), state}
  end

  @impl true
  def handle_info(:deadline, state) do
    Signals.emit(:mes_deadline_reached, %{run_id: state.run_id, team_name: state.team_name})
    {:noreply, %{state | deadline_passed: true}}
  end

  def handle_info(:check_liveness, state) do
    if tmux_session_alive?(state.session) do
      schedule_liveness_check()
      {:noreply, state}
    else
      Signals.emit(:mes_tmux_gone, %{run_id: state.run_id, session: state.session})
      {:stop, :normal, state}
    end
  end

  def handle_info(
        %Message{name: :mes_quality_gate_failed, data: %{run_id: run_id} = data},
        %{run_id: run_id} = state
      ) do
    failures = state.gate_failures + 1
    TeamSpawner.spawn_corrective_agent(state.run_id, state.session, data[:reason], failures)
    {:noreply, %{state | gate_failures: failures}}
  end

  def handle_info(
        %Message{name: :mes_quality_gate_escalated, data: %{run_id: run_id}},
        %{run_id: run_id} = state
      ) do
    {:noreply, %{state | deadline_passed: true}}
  end

  def handle_info(%Message{}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Signals.emit(:mes_run_terminated, %{run_id: state.run_id})
    # MES agents are under Fleet.TeamSupervisor and self-terminate when their
    # tmux windows die (liveness_poll). RunProcess does NOT own agent lifecycle.
    :ok
  end

  # ── Private ────────────────────────────────────────────────────────

  defp schedule_liveness_check do
    Process.send_after(self(), :check_liveness, @liveness_interval_ms)
  end

  defp tmux_session_alive?(session) do
    Tmux.available?(session)
  end
end
