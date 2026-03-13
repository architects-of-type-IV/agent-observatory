defmodule Ichor.Mes.RunProcess do
  @moduledoc """
  GenServer representing a single MES manufacturing run.

  Manages the lifecycle of one 5-agent team:
    1. Creates tmux session with agent windows
    2. Registers agents in BEAM fleet
    3. Owns the kill timer (10-minute timeout)
    4. Cleans up on termination (disband team + kill tmux)

  Registered in Ichor.Mes.Registry via `{:mes_run, run_id}`.
  Supervised under Ichor.Mes.RunSupervisor (DynamicSupervisor).
  """

  use GenServer, restart: :temporary

  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Mes.TeamSpawner
  alias Ichor.Signals

  @kill_timeout_ms :timer.minutes(10)

  defstruct [:run_id, :team_name, :session, agents: []]

  # ── Public API ──────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(run_id))
  end

  @spec via(String.t()) :: {:via, Registry, {Ichor.Mes.Registry, {:mes_run, String.t()}}}
  def via(run_id), do: {:via, Registry, {Ichor.Mes.Registry, {:mes_run, run_id}}}

  @spec lookup(String.t()) :: pid() | nil
  def lookup(run_id) do
    case Registry.lookup(Ichor.Mes.Registry, {:mes_run, run_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @spec list_all() :: [{String.t(), pid()}]
  def list_all do
    Registry.select(Ichor.Mes.Registry, [
      {{{:mes_run, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    team_name = Keyword.fetch!(opts, :team_name)

    state = %__MODULE__{
      run_id: run_id,
      team_name: team_name,
      session: "mes-#{run_id}"
    }

    Signals.emit(:mes_run_init, %{run_id: run_id, team_name: team_name})
    {:ok, state, {:continue, :spawn_team}}
  end

  @impl true
  def handle_continue(:spawn_team, state) do
    case TeamSpawner.spawn_run(state.run_id, state.team_name) do
      {:ok, session} ->
        Ichor.Mes.Janitor.monitor_run(state.run_id, self())
        Process.send_after(self(), :kill_timeout, @kill_timeout_ms)
        Signals.emit(:mes_run_started, %{run_id: state.run_id, session: session})
        {:noreply, %{state | session: session}}

      {:error, reason} ->
        Signals.emit(:mes_cycle_failed, %{run_id: state.run_id, reason: inspect(reason)})
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(:kill_timeout, state) do
    Signals.emit(:mes_cycle_timeout, %{run_id: state.run_id, team_name: state.team_name})
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    Signals.emit(:mes_run_terminated, %{run_id: state.run_id})
    # Disband the team first -- terminates all AgentProcesses under TeamSupervisor
    FleetSupervisor.disband_team(state.team_name)
    # Then kill the tmux session and clean up prompt files
    TeamSpawner.kill_session(state.session)
    :ok
  end
end
