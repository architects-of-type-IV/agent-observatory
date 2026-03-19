defmodule Ichor.Projects.PlanRunner do
  @moduledoc """
  GenServer representing a single Genesis mode run.

  Mirrors MES RunProcess lifecycle:
    1. Spawned by ModeSpawner after team creation
    2. Monitors tmux session liveness (30s poll)
    3. Listens for coordinator -> operator delivery (completion signal)
    4. Tears down team via TeamLaunch (kills session + disbands fleet + cleans prompt files)

  Registered in Ichor.Registry via `{:genesis_run, run_id}`.
  Supervised under Ichor.Projects.PlanRunSupervisor (DynamicSupervisor).
  """

  use GenServer, restart: :temporary

  alias Ichor.Control.Lifecycle.TeamLaunch
  alias Ichor.Control.Lifecycle.TeamSpec
  alias Ichor.Control.Lifecycle.TmuxLauncher
  alias Ichor.Projects.RunnerRegistry
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @liveness_interval_ms :timer.seconds(30)

  @enforce_keys [:run_id, :mode, :team_spec]
  defstruct [:run_id, :mode, :team_spec, :node_id]

  @type t :: %__MODULE__{
          run_id: String.t(),
          mode: String.t(),
          team_spec: TeamSpec.t(),
          node_id: String.t() | nil
        }

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(run_id))
  end

  @doc "Returns the via-tuple for Registry-based name lookup."
  @spec via(String.t()) :: {:via, Registry, {Ichor.Registry, {:genesis_run, String.t()}}}
  def via(run_id), do: RunnerRegistry.via(:genesis_run, run_id)

  @doc "Returns the pid for run_id if alive, or nil."
  @spec lookup(String.t()) :: pid() | nil
  def lookup(run_id), do: RunnerRegistry.lookup(:genesis_run, run_id)

  @doc "Lists all active genesis run IDs and their process PIDs."
  @spec list_all() :: [{String.t(), pid()}]
  def list_all, do: RunnerRegistry.list_all(:genesis_run)

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    mode = Keyword.fetch!(opts, :mode)
    team_spec = Keyword.fetch!(opts, :team_spec)
    node_id = Keyword.get(opts, :node_id)

    state = %__MODULE__{
      run_id: run_id,
      mode: mode,
      team_spec: team_spec,
      node_id: node_id
    }

    Signals.subscribe(:messages)
    schedule_liveness_check()

    Signals.emit(:genesis_run_init, %{
      run_id: run_id,
      mode: mode,
      session: team_spec.session
    })

    {:ok, state}
  end

  @impl true
  def handle_info(:check_liveness, state) do
    if TmuxLauncher.available?(state.team_spec.session) do
      schedule_liveness_check()
      {:noreply, state}
    else
      Signals.emit(:genesis_tmux_gone, %{
        run_id: state.run_id,
        session: state.team_spec.session
      })

      cleanup(state)
      {:stop, :normal, state}
    end
  end

  def handle_info(
        %Message{
          name: :message_delivered,
          data: %{msg_map: %{to: "operator", from: from}}
        },
        state
      )
      when is_binary(from) do
    if String.starts_with?(from, state.team_spec.session) do
      Signals.emit(:genesis_run_complete, %{
        run_id: state.run_id,
        mode: state.mode,
        session: state.team_spec.session,
        delivered_by: from
      })

      cleanup(state)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(%Message{}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Signals.emit(:genesis_run_terminated, %{run_id: state.run_id, mode: state.mode})
    :ok
  end

  defp cleanup(state) do
    TeamLaunch.teardown(state.team_spec)
  end

  defp schedule_liveness_check do
    Process.send_after(self(), :check_liveness, @liveness_interval_ms)
  end
end
