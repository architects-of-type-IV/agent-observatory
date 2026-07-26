defmodule Signals.Examples.LoopDetected do
  @moduledoc """
  The same tool invoked N times running by one agent.

  A tool call is not a problem. A tool call repeated is a problem, and the
  difference lives nowhere in either event — only in their adjacency. The agent
  is busy, responsive, and making no progress, which every liveness check reads
  as healthy.

  Watches one topic and concludes from sequence alone.
  """

  use Signals.Signal

  @repeats 3
  @window 5

  @impl true
  def name, do: "loop_detected"

  @impl true
  def topics, do: ["agent.tool.invoked"]

  @impl true
  def init(key), do: %{key: key, recent: []}

  @impl true
  def handle_event(%Event{data: data}, state) do
    tool = data && (Map.get(data, "tool") || Map.get(data, :tool))
    %{state | recent: Enum.take([tool | state.recent], @window)}
  end

  @impl true
  def ready?(%{recent: [tool | _] = recent}, _trigger) when not is_nil(tool) do
    recent |> Enum.take(@repeats) |> Enum.uniq() |> length() == 1 and
      length(recent) >= @repeats
  end

  def ready?(_state, _trigger), do: false

  @impl true
  def build_emission(%{key: key, recent: [tool | _]}) do
    %{agent_id: key, tool: tool, repeats: @repeats, reason: "same tool #{@repeats}x running"}
  end

  def build_emission(_state), do: nil

  @impl true
  def reset(state), do: %{state | recent: []}
end

defmodule Signals.Examples.AgentSilent do
  @moduledoc """
  An agent that started and then went quiet past a threshold.

  Concludes from **absence**, which is why it needs a timer: no event will ever
  arrive to say "nothing is happening". Any activity resets the clock; the timer
  is what notices the clock ran out.
  """

  use Signals.Signal

  @silent_after_ms 60_000

  @impl true
  def name, do: "agent_silent"

  @impl true
  def topics, do: ["agent.*"]

  @impl true
  def interval, do: 10_000

  @impl true
  def init(key), do: %{key: key, last_seen: nil, alerted?: false}

  @impl true
  def handle_event(%Event{time: time}, state),
    do: %{state | last_seen: time, alerted?: false}

  @impl true
  def ready?(%{last_seen: nil}, _trigger), do: false
  def ready?(%{alerted?: true}, _trigger), do: false

  # Only the timer can conclude silence — an event arriving is evidence against it.
  def ready?(%{last_seen: last}, :timer),
    do: DateTime.diff(DateTime.utc_now(), last, :millisecond) > @silent_after_ms

  def ready?(_state, :event), do: false

  @impl true
  def build_emission(%{key: key, last_seen: last}) do
    %{
      agent_id: key,
      silent_for_ms: DateTime.diff(DateTime.utc_now(), last, :millisecond),
      last_seen: last
    }
  end

  # Keep last_seen: the agent is still silent, and re-arming from nothing would
  # restart the clock and never fire again. Latch instead.
  @impl true
  def reset(state), do: %{state | alerted?: true}
end

defmodule Signals.Examples.CrashCascade do
  @moduledoc """
  Several agents crashing inside a short window.

  One crash is noise; OTP restarts it and nobody needs telling. Several across
  *different* agents in a minute is a systemic fault, and no individual crash
  event knows that.

  The correlation is across subjects, so this signal accumulates fleet-wide.
  Partitioned per agent — the default — it could never see more than one agent
  and would silently never fire. The emitter of `agent.crashed` is right to set
  the agent as subject; deciding to count across agents is this signal's
  business, not the emitter's.
  """

  use Signals.Signal

  @threshold 3
  @window_ms 60_000

  @impl true
  def name, do: "crash_cascade"

  @impl true
  def topics, do: ["agent.crashed"]

  @impl true
  def partition_key(_event), do: "fleet"

  @impl true
  def interval, do: 15_000

  @impl true
  def init(key), do: %{key: key, crashes: []}

  @impl true
  def handle_event(%Event{time: time, subject: subject, data: data}, state) do
    agent = subject || (data && (Map.get(data, "agent_id") || Map.get(data, :agent_id)))
    %{state | crashes: [{agent, time} | prune(state.crashes)]}
  end

  @impl true
  def ready?(%{crashes: crashes}, _trigger) do
    crashes
    |> prune()
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> length()
    |> Kernel.>=(@threshold)
  end

  @impl true
  def build_emission(%{crashes: crashes}) do
    recent = prune(crashes)
    %{agents: recent |> Enum.map(&elem(&1, 0)) |> Enum.uniq(), count: length(recent)}
  end

  @impl true
  def reset(state), do: %{state | crashes: []}

  defp prune(crashes) do
    cutoff = DateTime.add(DateTime.utc_now(), -@window_ms, :millisecond)
    Enum.filter(crashes, fn {_agent, time} -> DateTime.compare(time, cutoff) == :gt end)
  end
end

defmodule Signals.Examples.FleetDegraded do
  @moduledoc """
  A meta-signal: several *different* signals firing at once.

  Any one conclusion may be local — one looping agent, one gone quiet. Several
  distinct kinds within a window is a different claim, about the fleet rather
  than any agent in it.

  It needs no special support. `topics: ["signal.*"]` subscribes it to other
  signals' conclusions, because an emission is an ordinary event. This is what
  "a signal is not a topic" buys.

  Like `Signals.Examples.CrashCascade` it accumulates fleet-wide: the incoming
  emissions carry whatever subject their own signal used, and correlating them
  per subject would put a per-agent conclusion and a fleet-wide one into
  different accumulators, where neither can see the other.
  """

  use Signals.Signal

  @distinct 2
  @window_ms 120_000

  @impl true
  def name, do: "fleet_degraded"

  @impl true
  def topics, do: ["signal.*"]

  @impl true
  def partition_key(_event), do: "fleet"

  @impl true
  def interval, do: 30_000

  @impl true
  def init(key), do: %{key: key, seen: []}

  @impl true
  def handle_event(%Event{time: time} = event, state) do
    %{state | seen: [{Event.signal_name(event), time} | prune(state.seen)]}
  end

  @impl true
  def ready?(%{seen: seen}, _trigger) do
    seen |> prune() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() >= @distinct
  end

  @impl true
  def build_emission(%{seen: seen}) do
    %{signals: seen |> prune() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()}
  end

  @impl true
  def reset(state), do: %{state | seen: []}

  defp prune(seen) do
    cutoff = DateTime.add(DateTime.utc_now(), -@window_ms, :millisecond)
    Enum.filter(seen, fn {_name, time} -> DateTime.compare(time, cutoff) == :gt end)
  end
end
