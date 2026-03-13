defmodule Ichor.Mes.Scheduler do
  @moduledoc """
  Fires every 60 seconds. Spawns one MES run per tick as a RunProcess
  under the Mes.RunSupervisor DynamicSupervisor.

  Active run count is derived from the Mes.Registry (no local state tracking).
  RunProcess owns its own kill timer. Cleanup is handled by Mes.Janitor.
  """

  use GenServer

  alias Ichor.Mes.RunProcess
  alias Ichor.Signals

  @tick_interval :timer.minutes(1)
  @max_concurrent 1

  # ── Public API ──────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec status() :: map()
  def status, do: GenServer.call(__MODULE__, :status)

  # ── GenServer Callbacks ─────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Signals.emit(:mes_scheduler_init, %{})
    schedule_tick()
    {:ok, %{tick: 0}}
  end

  @impl true
  def handle_info(:tick, state) do
    active = length(RunProcess.list_all())
    Signals.emit(:mes_tick, %{tick: state.tick, active_runs: active})

    if active < @max_concurrent do
      spawn_run()
    else
      Signals.emit(:mes_cycle_skipped, %{tick: state.tick, active_runs: active})
    end

    schedule_tick()
    {:noreply, %{state | tick: state.tick + 1}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       tick: state.tick,
       active_runs: length(RunProcess.list_all()),
       next_tick_in: @tick_interval
     }, state}
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)

  defp spawn_run do
    run_id = generate_run_id()
    team_name = "mes-#{run_id}"

    case DynamicSupervisor.start_child(
           Ichor.Mes.RunSupervisor,
           {RunProcess, run_id: run_id, team_name: team_name}
         ) do
      {:ok, _pid} ->
        Signals.emit(:mes_cycle_started, %{run_id: run_id, team_name: team_name})

      {:error, reason} ->
        Signals.emit(:mes_cycle_failed, %{run_id: run_id, reason: inspect(reason)})
    end
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
end
