defmodule Ichor.Subsystems.PulseMonitor do
  @moduledoc """
  Real-time signal frequency analyzer that detects anomalous burst
  patterns and sustained silence across the Ichor nervous system.

  Architecture: GenServer + ETS. Subscribes to all signal categories.
  On each signal, increments a per-category counter with a timestamp.
  A 5s tick prunes expired entries, recomputes baselines, and checks
  burst/silence thresholds.

  The PubSub topic `subsystem:pulse_monitor` is this subsystem's address.
  Any module can send control signals to it via Ichor.Signals.emit/3.
  """

  use GenServer

  require Logger

  @behaviour Ichor.Mes.Subsystem

  @table :pulse_monitor_counters
  @tick_interval 5_000
  @window_seconds 30
  @burst_multiplier 3.0
  @silence_threshold_seconds 60

  # ── Subsystem Behaviour ─────────────────────────────────────────────

  @impl Ichor.Mes.Subsystem
  def info do
    %Ichor.Mes.Subsystem.Info{
      name: "Pulse Monitor",
      module: __MODULE__,
      description:
        "Real-time signal frequency analyzer that detects anomalous burst patterns and sustained silence.",
      topic: "subsystem:pulse_monitor",
      version: "0.1.0",
      architecture:
        "GenServer with ETS table for counters. 5s tick prunes windows and checks thresholds.",
      signals_emitted: [:pulse_anomaly_detected, :pulse_silence_detected, :pulse_baseline_updated],
      signals_subscribed: [:all],
      features: [
        "Sliding-window signal frequency histogram (per category, #{@window_seconds}s window)",
        "Burst detection: alert when any category exceeds #{@burst_multiplier}x baseline rate",
        "Silence detection: alert when expected signals go missing for >#{@silence_threshold_seconds}s",
        "ETS-backed frequency counters for zero-copy reads from dashboard"
      ],
      use_cases: [
        "Detect runaway signal storms from a misbehaving agent",
        "Alert when fleet heartbeats stop arriving",
        "Surface abnormal entropy spikes that correlate with agent crashes",
        "Provide frequency baseline data for capacity planning"
      ],
      dependencies: [Ichor.Signals, :ets]
    }
  end

  @impl Ichor.Mes.Subsystem
  def start do
    case GenServer.start_link(__MODULE__, [], name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Ichor.Mes.Subsystem
  def handle_signal(%{name: name, data: data}) do
    GenServer.cast(__MODULE__, {:signal, name, data})
    :ok
  end

  @impl Ichor.Mes.Subsystem
  def stop do
    GenServer.stop(__MODULE__, :normal)
    :ok
  catch
    :exit, _ -> :ok
  end

  # ── Public Read API (ETS direct, no GenServer bottleneck) ──────────

  @spec get_frequencies() :: %{atom() => non_neg_integer()}
  def get_frequencies do
    if :ets.whereis(@table) != :undefined do
      now = System.monotonic_time(:second)
      cutoff = now - @window_seconds

      @table
      |> :ets.tab2list()
      |> Enum.filter(fn {_category, ts} -> ts > cutoff end)
      |> Enum.group_by(fn {category, _ts} -> category end)
      |> Map.new(fn {category, entries} -> {category, length(entries)} end)
    else
      %{}
    end
  end

  @spec get_baselines() :: %{atom() => float()}
  def get_baselines do
    GenServer.call(__MODULE__, :get_baselines)
  catch
    :exit, _ -> %{}
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])
    tick_ref = schedule_tick()

    categories = subscribe_all()
    Logger.info("[PulseMonitor] Started. Subscribed to #{length(categories)} categories.")

    {:ok,
     %{
       table: table,
       tick_ref: tick_ref,
       baselines: %{},
       last_seen: %{}
     }}
  end

  @impl GenServer
  def handle_cast({:signal, category, _data}, state) do
    now = System.monotonic_time(:second)
    :ets.insert(@table, {category, now})
    last_seen = Map.put(state.last_seen, category, now)
    {:noreply, %{state | last_seen: last_seen}}
  end

  @impl GenServer
  def handle_call(:get_baselines, _from, state) do
    {:reply, state.baselines, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    now = System.monotonic_time(:second)
    prune_expired(now)
    frequencies = compute_frequencies(now)
    new_baselines = update_baselines(state.baselines, frequencies)

    check_bursts(frequencies, new_baselines)
    check_silence(state.last_seen, now)

    emit_baseline_update(new_baselines)

    tick_ref = schedule_tick()
    {:noreply, %{state | baselines: new_baselines, tick_ref: tick_ref}}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, _state) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    unsubscribe_all()
    :ok
  end

  # ── Private ────────────────────────────────────────────────────────

  defp subscribe_all do
    categories = Ichor.Signals.Catalog.categories()
    Enum.each(categories, &Ichor.Signals.subscribe/1)
    categories
  rescue
    _ ->
      Logger.warning("[PulseMonitor] Could not subscribe to signal categories")
      []
  end

  defp unsubscribe_all do
    Ichor.Signals.Catalog.categories()
    |> Enum.each(fn cat ->
      topic = Ichor.Signals.Topics.category(cat)
      Phoenix.PubSub.unsubscribe(Ichor.PubSub, topic)
    end)
  rescue
    _ -> :ok
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end

  defp prune_expired(now) do
    cutoff = now - @window_seconds

    @table
    |> :ets.tab2list()
    |> Enum.each(fn {_cat, ts} = entry ->
      if ts <= cutoff, do: :ets.delete_object(@table, entry)
    end)
  end

  defp compute_frequencies(now) do
    cutoff = now - @window_seconds

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {_cat, ts} -> ts > cutoff end)
    |> Enum.group_by(fn {cat, _ts} -> cat end)
    |> Map.new(fn {cat, entries} -> {cat, length(entries)} end)
  end

  defp update_baselines(old_baselines, frequencies) do
    # Exponential moving average: baseline = 0.7 * old + 0.3 * current
    Map.merge(old_baselines, frequencies, fn _cat, old, current ->
      0.7 * old + 0.3 * current
    end)
    |> Map.merge(
      Map.new(frequencies, fn {cat, count} ->
        {cat, Map.get(old_baselines, cat, count * 1.0)}
      end),
      fn _cat, updated, _new -> updated end
    )
  end

  defp check_bursts(frequencies, baselines) do
    Enum.each(frequencies, fn {category, count} ->
      baseline = Map.get(baselines, category, 0.0)

      if baseline > 0 and count > baseline * @burst_multiplier do
        Ichor.Signals.emit(:pulse_anomaly_detected, %{
          category: category,
          count: count,
          baseline: Float.round(baseline, 2),
          multiplier: Float.round(count / baseline, 2)
        })

        Logger.warning(
          "[PulseMonitor] Burst detected in #{category}: #{count} signals (baseline: #{Float.round(baseline, 2)})"
        )
      end
    end)
  rescue
    _ -> :ok
  end

  defp check_silence(last_seen, now) do
    Enum.each(last_seen, fn {category, last_ts} ->
      gap = now - last_ts

      if gap > @silence_threshold_seconds do
        Ichor.Signals.emit(:pulse_silence_detected, %{
          category: category,
          gap_seconds: gap
        })

        Logger.warning("[PulseMonitor] Silence in #{category}: #{gap}s since last signal")
      end
    end)
  rescue
    _ -> :ok
  end

  defp emit_baseline_update(baselines) do
    if map_size(baselines) > 0 do
      rounded =
        Map.new(baselines, fn {cat, val} -> {cat, Float.round(val, 2)} end)

      Ichor.Signals.emit(:pulse_baseline_updated, %{baselines: rounded})
    end
  rescue
    _ -> :ok
  end
end
