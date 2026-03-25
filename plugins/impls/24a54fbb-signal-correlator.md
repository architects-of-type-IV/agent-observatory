# Implementation Brief: Signal Correlator
**Brief ID:** 24a54fbb
**Plugin:** `Ichor.Plugins.SignalCorrelator`
**Version:** 0.1.0

---

## Signal Catalog Additions

Add to `lib/ichor/signals/catalog.ex`:

```elixir
@correlator_defs %{
  correlation_detected: %{
    category: :monitoring,
    keys: [:agents, :pattern, :score, :window_start, :window_end],
    doc: "Cross-agent signal correlation exceeded threshold"
  },
  bottleneck_identified: %{
    category: :monitoring,
    keys: [:agent_id, :signal_name, :frequency, :window_ms],
    doc: "Single agent or signal type identified as pipeline bottleneck"
  },
  pipeline_stall_detected: %{
    category: :monitoring,
    keys: [:agents, :stall_duration_ms, :last_signal_at],
    doc: "No significant signals from tracked agents for stall_duration_ms"
  }
}
```

Merge `@correlator_defs` into `@signals`.

---

## Module Structure

```
lib/ichor/plugins/signal_correlator/
  correlator.ex          # Main GenServer with sliding window buffer
  analysis.ex            # Pure functions: scoring, bottleneck detection, stall detection
```

---

## Supervisor Registration

Add to application supervision tree (appropriate Infrastructure supervisor):

```elixir
{Ichor.Plugins.SignalCorrelator.Correlator, []},
```

This is a singleton GenServer — not per-run. It observes the whole fleet.

---

## Correlator GenServer State

```elixir
defmodule Ichor.Plugins.SignalCorrelator.Correlator do
  use GenServer

  @window_size 100          # max buffered signal events
  @window_ms 30_000         # 30-second rolling window
  @correlation_threshold 0.7
  @stall_threshold_ms 60_000
  @tick_ms 15_000

  # window: [{agent_id, signal_name, timestamp}]
  # latency: %{agent_id => [duration_ms]}
  defstruct window: [], latency: %{}
```

### Subscriptions in init/1

```elixir
@impl true
def init(_opts) do
  Ichor.Signals.subscribe(:agent)       # agent_event, nudge_*, agent_blocked
  Ichor.Signals.subscribe(:monitoring)  # agent_blocked, watchdog_sweep, gate_failed
  Ichor.Signals.subscribe(:fleet)       # agent_started, agent_stopped, agent_evicted
  Ichor.Signals.subscribe(:gateway)     # entropy_alert
  Ichor.Signals.subscribe(:mes)         # mes_run_started, mes_run_terminated, mes_agent_stopped
  Process.send_after(self(), :tick, @tick_ms)
  {:ok, %__MODULE__{}}
end
```

### handle_info: Window accumulation

On every `%Message{}`, extract `{agent_id, signal_name, now}` and append to window:

```elixir
@impl true
def handle_info(%Ichor.Signals.Message{name: name, data: data} = _msg, state) do
  agent_id = extract_agent_id(data)
  entry = {agent_id, name, System.monotonic_time(:millisecond)}
  window = slide_window([entry | state.window], @window_size, @window_ms)
  {:noreply, %{state | window: window}}
end
```

`extract_agent_id/1` tries keys in order: `:session_id`, `:agent_id`, `:agent_name`, then falls back to `"system"`.

### handle_info: Tick — analysis pass

```elixir
@impl true
def handle_info(:tick, state) do
  now = System.monotonic_time(:millisecond)

  # Run all analysis passes (pure, in analysis.ex)
  correlations = Analysis.find_correlations(state.window, @correlation_threshold)
  bottlenecks = Analysis.find_bottlenecks(state.window)
  stall = Analysis.detect_stall(state.window, now, @stall_threshold_ms)

  Enum.each(correlations, fn c ->
    Ichor.Signals.emit(:correlation_detected, c)
  end)

  Enum.each(bottlenecks, fn b ->
    Ichor.Signals.emit(:bottleneck_identified, b)
  end)

  if stall do
    Ichor.Signals.emit(:pipeline_stall_detected, stall)
  end

  Process.send_after(self(), :tick, @tick_ms)
  {:noreply, state}
end

@impl true
def handle_info(_msg, state), do: {:noreply, state}
```

---

## Analysis Module (Pure)

```elixir
defmodule Ichor.Plugins.SignalCorrelator.Analysis do
  @moduledoc """
  Pure analysis functions over signal event windows.
  No side effects. All functions take a window list and return findings.

  Window entry format: {agent_id :: String.t() | nil, signal_name :: atom(), ts_ms :: integer()}
  """

  @doc """
  Finds agent pairs or groups with high signal co-occurrence within window.
  Returns list of correlation maps or [].
  """
  @spec find_correlations([tuple()], float()) :: [map()]
  def find_correlations(window, threshold) do
    # Group by agent_id, compute pair-wise co-occurrence ratio
    # Emit when ratio >= threshold
    # Implementation: count shared signal_names across agent pairs within window
    agents = window |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.reject(&is_nil/1)

    for a <- agents, b <- agents, a < b do
      a_signals = window |> Enum.filter(&(elem(&1, 0) == a)) |> Enum.map(&elem(&1, 1)) |> MapSet.new()
      b_signals = window |> Enum.filter(&(elem(&1, 0) == b)) |> Enum.map(&elem(&1, 1)) |> MapSet.new()
      shared = MapSet.intersection(a_signals, b_signals) |> MapSet.size()
      total = MapSet.union(a_signals, b_signals) |> MapSet.size()
      score = if total == 0, do: 0.0, else: shared / total
      {a, b, score}
    end
    |> Enum.filter(fn {_, _, score} -> score >= threshold end)
    |> Enum.map(fn {a, b, score} ->
      ts = window |> Enum.map(&elem(&1, 2))
      %{agents: [a, b], pattern: :co_occurrence, score: score,
        window_start: Enum.min(ts, fn -> 0 end),
        window_end: Enum.max(ts, fn -> 0 end)}
    end)
  end

  @doc """
  Finds agents or signal names that appear disproportionately often in the window.
  A bottleneck is an agent that emits >30% of all signals in the window.
  """
  @spec find_bottlenecks([tuple()]) :: [map()]
  def find_bottlenecks([]), do: []

  def find_bottlenecks(window) do
    total = length(window)
    window
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.filter(fn {_agent, entries} -> length(entries) / total > 0.3 end)
    |> Enum.map(fn {agent_id, entries} ->
      signal_counts = Enum.frequencies_by(entries, &elem(&1, 1))
      top_signal = Enum.max_by(signal_counts, &elem(&1, 1), fn -> {:unknown, 0} end)
      %{agent_id: agent_id,
        signal_name: elem(top_signal, 0),
        frequency: length(entries),
        window_ms: window_duration_ms(window)}
    end)
  end

  @doc """
  Returns a stall map if no signals in the window are newer than stall_threshold_ms,
  or nil if activity is present.
  """
  @spec detect_stall([tuple()], integer(), integer()) :: map() | nil
  def detect_stall([], _now, _threshold), do: nil

  def detect_stall(window, now, threshold_ms) do
    last_ts = window |> Enum.map(&elem(&1, 2)) |> Enum.max(fn -> now end)
    stall_ms = now - last_ts
    if stall_ms >= threshold_ms do
      agents = window |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.reject(&is_nil/1)
      %{agents: agents, stall_duration_ms: stall_ms, last_signal_at: last_ts}
    else
      nil
    end
  end

  defp window_duration_ms([]), do: 0
  defp window_duration_ms(window) do
    ts = Enum.map(window, &elem(&1, 2))
    Enum.max(ts) - Enum.min(ts)
  end
end
```

---

## Window Pruning

```elixir
# In Correlator — prune by both size and age
defp slide_window(window, max_size, max_ms) do
  cutoff = System.monotonic_time(:millisecond) - max_ms
  window
  |> Enum.filter(fn {_, _, ts} -> ts >= cutoff end)
  |> Enum.take(max_size)
end
```

---

## Key Constraints

- All analysis logic is in `Analysis` (pure, no side effects). `Correlator` handles signal I/O only.
- `Analysis` functions must return `[]` / `nil` on empty window — never crash.
- Do NOT call `EntropyTracker` directly from the Correlator — react to its `entropy_alert` signals.
- Do NOT use `Ichor.Projector.SignalBuffer` for storage — maintain an in-process window list in GenServer state.
- `extract_agent_id/1` must never raise — use pattern matching with fallback.
- New catalog signals (`correlation_detected`, `bottleneck_identified`, `pipeline_stall_detected`) must be added to Catalog before first emit.
- `find_correlations/2` is O(n²) over unique agents. Cap agent count in analysis to 20 to bound compute on a large fleet.

---

## Verification

```bash
mix compile --warnings-as-errors
# iex smoke test:
# iex> alias Ichor.Plugins.SignalCorrelator.Analysis
# iex> window = [{"agent-1", :agent_blocked, 100}, {"agent-2", :agent_blocked, 150}, {"agent-1", :nudge_sent, 200}]
# iex> Analysis.find_correlations(window, 0.4)
# => [%{agents: ["agent-1", "agent-2"], ...}]
# iex> Analysis.find_bottlenecks(window)
# => [%{agent_id: "agent-1", ...}]
```
