defmodule Ichor.Signals.Benchmark do
  @moduledoc """
  Pipeline throughput and latency benchmarks. Run from iex:

      Ichor.Signals.Benchmark.throughput(10_000)
      Ichor.Signals.Benchmark.latency(100)
      Ichor.Signals.Benchmark.crash_recovery()
      Ichor.Signals.Benchmark.concurrent(10, 1_000)
  """

  alias Ichor.Events.{Event, Ingress}

  @doc "Push N events and measure wall-clock time. Reports events/sec."
  @spec throughput(pos_integer()) :: map()
  def throughput(n \\ 10_000) do
    start = System.monotonic_time(:microsecond)

    for i <- 1..n do
      Ingress.push(Event.new("benchmark.throughput.event", "bench-#{rem(i, 100)}", %{i: i}))
    end

    elapsed_us = System.monotonic_time(:microsecond) - start
    elapsed_ms = elapsed_us / 1000
    rate = n / (elapsed_us / 1_000_000)

    IO.puts(
      "Pushed #{n} events in #{Float.round(elapsed_ms, 1)}ms (#{Float.round(rate, 0)} events/sec)"
    )

    %{events: n, elapsed_ms: Float.round(elapsed_ms, 1), events_per_sec: Float.round(rate, 0)}
  end

  @doc """
  Push N events through ToolBudget signal module and measure how long
  until the GenStage pipeline drains and a SignalProcess is created.
  """
  @spec latency(pos_integer()) :: map()
  def latency(n \\ 100) do
    key = "latency-bench-#{System.unique_integer([:positive])}"
    start = System.monotonic_time(:microsecond)

    for i <- 1..n do
      Ingress.push(
        Event.new("agent.tool.completed", key, %{
          i: i,
          tool_name: "Bash",
          session_id: key
        })
      )
    end

    # Wait for events to drain through GenStage
    Process.sleep(100)
    elapsed_us = System.monotonic_time(:microsecond) - start

    case Registry.lookup(Ichor.Signals.ProcessRegistry, {Ichor.Signals.Agent.ToolBudget, key}) do
      [{_pid, _}] ->
        IO.puts("#{n} events routed to SignalProcess in #{Float.round(elapsed_us / 1000, 1)}ms")

      [] ->
        IO.puts(
          "SignalProcess not created after #{n} events (#{Float.round(elapsed_us / 1000, 1)}ms)"
        )
    end

    %{events: n, elapsed_ms: Float.round(elapsed_us / 1000, 1)}
  end

  @doc "Test crash recovery: kill a SignalProcess and verify a new one is created on next event."
  @spec crash_recovery() :: map()
  def crash_recovery do
    key = "crash-bench-#{System.unique_integer([:positive])}"

    Ingress.push(Event.new("agent.tool.completed", key, %{tool_name: "test", session_id: key}))

    Process.sleep(50)

    case Registry.lookup(Ichor.Signals.ProcessRegistry, {Ichor.Signals.Agent.ToolBudget, key}) do
      [{pid, _}] ->
        IO.puts("SignalProcess started: #{inspect(pid)}")
        Process.exit(pid, :kill)
        Process.sleep(50)

        Ingress.push(
          Event.new("agent.tool.completed", key, %{tool_name: "test2", session_id: key})
        )

        Process.sleep(50)

        case Registry.lookup(
               Ichor.Signals.ProcessRegistry,
               {Ichor.Signals.Agent.ToolBudget, key}
             ) do
          [{new_pid, _}] ->
            IO.puts("New SignalProcess after crash: #{inspect(new_pid)} (healed)")
            %{status: :healed, old_pid: pid, new_pid: new_pid}

          [] ->
            IO.puts("WARNING: SignalProcess not recreated after crash")
            %{status: :not_healed}
        end

      [] ->
        IO.puts("ERROR: Could not create initial SignalProcess")
        %{status: :error}
    end
  end

  @doc "Stress test: push events from N concurrent processes."
  @spec concurrent(pos_integer(), pos_integer()) :: map()
  def concurrent(processes \\ 10, events_per \\ 1_000) do
    start = System.monotonic_time(:microsecond)

    tasks =
      for p <- 1..processes do
        Task.async(fn ->
          for i <- 1..events_per do
            Ingress.push(Event.new("benchmark.concurrent.event", "proc-#{p}", %{i: i}))
          end
        end)
      end

    Task.await_many(tasks, 30_000)

    elapsed_us = System.monotonic_time(:microsecond) - start
    total = processes * events_per
    rate = total / (elapsed_us / 1_000_000)

    IO.puts(
      "#{processes} processes x #{events_per} events = #{total} total in " <>
        "#{Float.round(elapsed_us / 1000, 1)}ms (#{Float.round(rate, 0)} events/sec)"
    )

    %{
      total: total,
      elapsed_ms: Float.round(elapsed_us / 1000, 1),
      events_per_sec: Float.round(rate, 0)
    }
  end
end
