defmodule Ichor.Factory.MesScheduler do
  @moduledoc """
  Fires every 60 seconds and spawns at most one MES planning run per tick.

  Supports pause/resume via `pause/0` and `resume/0`. Paused state persists
  across restarts via a file flag at `~/.ichor/mes/paused`.
  """

  use GenServer

  alias Ichor.Factory.Runner
  alias Ichor.Signals

  @tick_interval :timer.minutes(1)
  @max_concurrent 1
  @pause_flag Path.join(File.cwd!(), "tmp/mes_paused")

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Returns current scheduler status including tick count and active run count."
  @spec status() :: map()
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Pauses the scheduler; persists the paused flag to disk."
  @spec pause() :: :ok
  def pause, do: GenServer.call(__MODULE__, :pause)

  @doc "Resumes a paused scheduler; removes the paused flag from disk."
  @spec resume() :: :ok
  def resume, do: GenServer.call(__MODULE__, :resume)

  @doc "Returns true if the scheduler is currently paused."
  @spec paused?() :: boolean()
  def paused?, do: GenServer.call(__MODULE__, :paused?)

  @impl true
  def init(_opts) do
    paused = File.exists?(@pause_flag)
    Signals.emit(:mes_scheduler_init, %{paused: paused})
    tick_ref = schedule_tick()
    {:ok, %{tick: 0, paused: paused, tick_ref: tick_ref}}
  end

  @impl true
  def handle_info(:tick, %{paused: true} = state) do
    Signals.emit(:mes_tick, %{tick: state.tick, active_runs: 0, paused: true})
    tick_ref = schedule_tick()
    {:noreply, %{state | tick: state.tick + 1, tick_ref: tick_ref}}
  end

  def handle_info(:tick, state) do
    all = Runner.list_all(:mes)
    total = length(all)

    active =
      Enum.count(all, fn {_run_id, pid} ->
        try do
          not GenServer.call(pid, :deadline_passed?, 1_000)
        catch
          :exit, _ -> false
        end
      end)

    Signals.emit(:mes_tick, %{tick: state.tick, active_runs: active, total_runs: total})

    if active < @max_concurrent do
      spawn_run()
    else
      Signals.emit(:mes_cycle_skipped, %{tick: state.tick, active_runs: active})
    end

    tick_ref = schedule_tick()
    {:noreply, %{state | tick: state.tick + 1, tick_ref: tick_ref}}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    File.mkdir_p!(Path.dirname(@pause_flag))
    File.write!(@pause_flag, "")
    Signals.emit(:mes_scheduler_paused, %{tick: state.tick})
    {:reply, :ok, %{state | paused: true}}
  end

  def handle_call(:resume, _from, %{paused: false} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:resume, _from, state) do
    File.rm(@pause_flag)
    cancel_tick(state)
    Signals.emit(:mes_scheduler_resumed, %{tick: state.tick})
    send(self(), :tick)
    {:reply, :ok, %{state | paused: false, tick_ref: nil}}
  end

  def handle_call(:paused?, _from, state) do
    {:reply, state.paused, state}
  end

  def handle_call(:status, _from, state) do
    all = Runner.list_all(:mes)

    active_count =
      Enum.count(all, fn {_run_id, pid} ->
        try do
          not GenServer.call(pid, :deadline_passed?, 1_000)
        catch
          :exit, _ -> false
        end
      end)

    {:reply,
     %{
       tick: state.tick,
       active_runs: active_count,
       total_runs: length(all),
       next_tick_in: @tick_interval,
       paused: state.paused
     }, state}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)

  defp cancel_tick(%{tick_ref: ref}) when is_reference(ref) do
    Process.cancel_timer(ref, async: false, info: false)
    :ok
  end

  defp cancel_tick(_state), do: :ok

  defp spawn_run do
    run_id = generate_run_id()
    team_name = "mes-#{run_id}"

    case Runner.start(:mes, run_id: run_id, team_name: team_name) do
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
