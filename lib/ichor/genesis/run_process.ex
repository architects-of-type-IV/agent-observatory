defmodule Ichor.Genesis.RunProcess do
  @moduledoc """
  GenServer representing a single Genesis mode run.

  Mirrors MES RunProcess lifecycle:
    1. Spawned by ModeSpawner after team creation
    2. Monitors tmux session liveness (30s poll)
    3. Listens for coordinator -> operator delivery (completion signal)
    4. Kills tmux session + disbands fleet team + cleans prompt files

  Registered in Ichor.Registry via `{:genesis_run, run_id}`.
  Supervised under Ichor.Genesis.RunSupervisor (DynamicSupervisor).
  """

  use GenServer, restart: :temporary

  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Genesis.ModeRunner
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @liveness_interval_ms :timer.seconds(30)

  defstruct [:run_id, :mode, :session, :node_id]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(run_id))
  end

  @spec via(String.t()) :: {:via, Registry, {Ichor.Registry, {:genesis_run, String.t()}}}
  def via(run_id), do: {:via, Registry, {Ichor.Registry, {:genesis_run, run_id}}}

  @spec lookup(String.t()) :: pid() | nil
  def lookup(run_id) do
    case Registry.lookup(Ichor.Registry, {:genesis_run, run_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @spec list_all() :: [{String.t(), pid()}]
  def list_all do
    Registry.select(Ichor.Registry, [
      {{{:genesis_run, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    mode = Keyword.fetch!(opts, :mode)
    session = Keyword.fetch!(opts, :session)
    node_id = Keyword.get(opts, :node_id)

    state = %__MODULE__{
      run_id: run_id,
      mode: mode,
      session: session,
      node_id: node_id
    }

    Signals.subscribe(:messages)
    schedule_liveness_check()

    Signals.emit(:genesis_run_init, %{
      run_id: run_id,
      mode: mode,
      session: session
    })

    {:ok, state}
  end

  @impl true
  def handle_info(:check_liveness, state) do
    case Tmux.available?(state.session) do
      true ->
        schedule_liveness_check()
        {:noreply, state}

      false ->
        Signals.emit(:genesis_tmux_gone, %{
          run_id: state.run_id,
          session: state.session
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
    case String.starts_with?(from, state.session) do
      true ->
        Signals.emit(:genesis_run_complete, %{
          run_id: state.run_id,
          mode: state.mode,
          session: state.session,
          delivered_by: from
        })

        cleanup(state)
        {:stop, :normal, state}

      false ->
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
    ModeRunner.kill_session(state.session, state.run_id, state.mode)
    FleetSupervisor.disband_team(state.session)
  end

  defp schedule_liveness_check do
    Process.send_after(self(), :check_liveness, @liveness_interval_ms)
  end
end
