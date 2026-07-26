defmodule SignalsTest do
  use Signals.SignalCase

  alias Signals.Examples.AgentSilent
  alias Signals.Examples.CrashCascade
  alias Signals.Examples.FleetDegraded
  alias Signals.Examples.LoopDetected
  alias Signals.Sink.Collector

  doctest Signals.Signal

  defp invoke(agent, tool),
    do: emit("agent.tool.invoked", subject: agent, data: %{"tool" => tool})

  describe "routing" do
    @tag signals: [LoopDetected]
    test "an event reaches a signal that declared its topic" do
      assert [LoopDetected] = invoke("agent-1", "Read")
    end

    @tag signals: [LoopDetected]
    test "an event no signal declared reaches nobody" do
      assert [] = emit("system.started")
    end

    @tag signals: [LoopDetected, AgentSilent]
    test "one event fans out to every interested signal" do
      # agent.tool.invoked matches LoopDetected exactly and AgentSilent's agent.*
      reached = invoke("agent-1", "Read")

      assert LoopDetected in reached
      assert AgentSilent in reached
    end

    @tag signals: [LoopDetected]
    test "different subjects get separate accumulators" do
      invoke("agent-1", "Read")
      invoke("agent-2", "Read")

      keys = Signals.accumulators() |> Enum.map(fn {_s, key, _pid} -> key end) |> Enum.sort()
      assert keys == ["agent-1", "agent-2"]
    end

    @tag signals: [LoopDetected]
    test "an accumulator is created only when an event arrives" do
      assert Signals.accumulators() == []
      invoke("agent-1", "Read")
      assert length(Signals.accumulators()) == 1
    end
  end

  describe "subscriptions/0" do
    @tag signals: [LoopDetected, FleetDegraded]
    test "reports the graph and flags meta-signals" do
      graph = Signals.subscriptions()

      loop = Enum.find(graph, &(&1.signal == LoopDetected))
      meta = Enum.find(graph, &(&1.signal == FleetDegraded))

      assert loop.topics == ["agent.tool.invoked"]
      refute loop.meta?
      assert meta.meta?
    end
  end

  describe "LoopDetected — correlation by sequence" do
    @tag signals: [LoopDetected], sink: Collector
    test "one invocation is not a loop" do
      invoke("agent-1", "Read")

      assert Collector.emissions() == []
    end

    @tag signals: [LoopDetected], sink: Collector
    test "the same tool three times running is" do
      for _ <- 1..3, do: invoke("agent-1", "Read")

      assert [emission] = Collector.emissions_of("loop_detected")
      assert emission.data.tool == "Read"
      assert emission.data.agent_id == "agent-1"
      assert emission.subject == "agent-1"
    end

    @tag signals: [LoopDetected], sink: Collector
    test "three different tools are not" do
      invoke("agent-1", "Read")
      invoke("agent-1", "Bash")
      invoke("agent-1", "Grep")

      assert Collector.emissions() == []
    end

    @tag signals: [LoopDetected], sink: Collector
    test "a different tool breaks the run" do
      invoke("agent-1", "Read")
      invoke("agent-1", "Read")
      invoke("agent-1", "Bash")
      invoke("agent-1", "Read")

      assert Collector.emissions() == []
    end

    @tag signals: [LoopDetected], sink: Collector
    test "state resets after emitting, so it takes three more to fire again" do
      for _ <- 1..3, do: invoke("agent-1", "Read")
      assert length(Collector.emissions()) == 1

      invoke("agent-1", "Read")
      invoke("agent-1", "Read")
      assert length(Collector.emissions()) == 1

      invoke("agent-1", "Read")
      assert length(Collector.emissions()) == 2
    end

    @tag signals: [LoopDetected], sink: Collector
    test "two agents accumulate independently" do
      invoke("agent-1", "Read")
      invoke("agent-2", "Read")
      invoke("agent-1", "Read")
      invoke("agent-1", "Read")

      assert [emission] = Collector.emissions_of("loop_detected")
      assert emission.subject == "agent-1"
    end

    @tag signals: [LoopDetected]
    test "peek/2 shows the partial conclusion" do
      invoke("agent-1", "Read")
      invoke("agent-1", "Read")

      assert %{recent: ["Read", "Read"]} = Signals.peek(LoopDetected, "agent-1")
    end
  end

  describe "AgentSilent — correlation by absence" do
    @tag signals: [AgentSilent], sink: Collector
    test "activity alone concludes nothing" do
      emit("agent.session.started", subject: "agent-1")
      tick(AgentSilent, "agent-1")

      assert Collector.emissions() == []
    end

    @tag signals: [AgentSilent], sink: Collector
    test "an event trigger never concludes silence" do
      # Only the timer can see absence; an arriving event is evidence against it.
      old = DateTime.add(DateTime.utc_now(), -3600, :second)
      Signals.emit_event(Event.new("agent.session.started", subject: "a", time: old))
      sync()

      assert Collector.emissions() == []
    end

    @tag signals: [AgentSilent], sink: Collector
    test "the timer concludes silence once the threshold passes" do
      old = DateTime.add(DateTime.utc_now(), -3600, :second)
      Signals.emit_event(Event.new("agent.session.started", subject: "a", time: old))
      sync()

      tick(AgentSilent, "a")

      assert [emission] = Collector.emissions_of("agent_silent")
      assert emission.data.agent_id == "a"
      assert emission.data.silent_for_ms > 60_000
    end

    @tag signals: [AgentSilent], sink: Collector
    test "it latches, so a persistently silent agent alerts once" do
      old = DateTime.add(DateTime.utc_now(), -3600, :second)
      Signals.emit_event(Event.new("agent.session.started", subject: "a", time: old))
      sync()

      tick(AgentSilent, "a")
      tick(AgentSilent, "a")
      tick(AgentSilent, "a")

      assert length(Collector.emissions_of("agent_silent")) == 1
    end

    @tag signals: [AgentSilent], sink: Collector
    test "new activity clears the latch so it can alert again" do
      old = DateTime.add(DateTime.utc_now(), -3600, :second)
      Signals.emit_event(Event.new("agent.session.started", subject: "a", time: old))
      sync()
      tick(AgentSilent, "a")
      assert length(Collector.emissions_of("agent_silent")) == 1

      Signals.emit_event(Event.new("agent.tool.invoked", subject: "a", time: old))
      sync()
      tick(AgentSilent, "a")

      assert length(Collector.emissions_of("agent_silent")) == 2
    end
  end

  describe "CrashCascade — correlation across subjects" do
    # The emitter sets the natural subject; CrashCascade partitions fleet-wide.
    defp crash(agent), do: emit("agent.crashed", subject: agent)

    @tag signals: [CrashCascade], sink: Collector
    test "one crash is noise" do
      crash("agent-1")

      assert Collector.emissions() == []
    end

    @tag signals: [CrashCascade], sink: Collector
    test "three distinct agents crashing is a cascade" do
      crash("agent-1")
      crash("agent-2")
      crash("agent-3")

      assert [emission] = Collector.emissions_of("crash_cascade")
      assert Enum.sort(emission.data.agents) == ["agent-1", "agent-2", "agent-3"]
    end

    @tag signals: [CrashCascade], sink: Collector
    test "one agent crashing repeatedly is not a cascade" do
      for _ <- 1..5, do: crash("agent-1")

      assert Collector.emissions() == []
    end
  end

  describe "meta-signals — a signal consuming signals" do
    @tag signals: [LoopDetected, CrashCascade, FleetDegraded], sink: Signals.Sink.Local
    test "an emission is an ordinary event, so a meta-signal accumulates it" do
      Signals.subscribe(["signal.fleet_degraded"])

      for _ <- 1..3, do: invoke("agent-1", "Read")
      crash("agent-1")
      crash("agent-2")
      crash("agent-3")

      assert_receive {:signal, %Event{type: "signal.fleet_degraded"} = event}, 1_000
      assert Enum.sort(event.data.signals) == ["crash_cascade", "loop_detected"]
    end

    @tag signals: [LoopDetected, FleetDegraded], sink: Signals.Sink.Local
    test "one kind of conclusion is not fleet-wide degradation" do
      Signals.subscribe(["signal.*"])

      for _ <- 1..3, do: invoke("agent-1", "Read")

      assert_receive {:signal, %Event{type: "signal.loop_detected"}}, 1_000
      refute_receive {:signal, %Event{type: "signal.fleet_degraded"}}, 100
    end

    @tag signals: [LoopDetected], sink: Signals.Sink.Local
    test "emissions carry a causal depth" do
      Signals.subscribe(["signal.*"])
      for _ <- 1..3, do: invoke("agent-1", "Read")

      assert_receive {:signal, event}, 1_000
      assert event.extensions[:depth] == 1
    end
  end

  describe "emission depth cutoff" do
    defmodule Echo do
      @moduledoc false
      use Signals.Signal

      @impl true
      def name, do: "echo"

      @impl true
      def topics, do: ["signal.*", "start.it"]

      @impl true
      def init(key), do: %{key: key, n: 0}

      @impl true
      def handle_event(_event, state), do: %{state | n: state.n + 1}

      @impl true
      def ready?(%{n: n}, _trigger), do: n > 0

      @impl true
      def build_emission(%{n: n}), do: %{n: n}

      @impl true
      def reset(state), do: %{state | n: 0}
    end

    @tag signals: [Echo], sink: Signals.Sink.Local, max_emission_depth: 3
    test "a signal feeding itself terminates instead of spinning" do
      # Without a depth cap this recurses until the VM gives out, and the loop
      # looks like healthy throughput from outside.
      Signals.emit("start.it", subject: "x")
      sync()

      assert Process.alive?(Signals.Registry.whereis(Echo, "x"))
    end
  end

  describe "durability" do
    @tag signals: [LoopDetected]
    test "an accumulator restores its partial conclusion after a restart" do
      invoke("agent-1", "Read")
      invoke("agent-1", "Read")

      pid = Signals.Registry.whereis(LoopDetected, "agent-1")
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, _, _}

      # One more should complete the run of three, not start a new one.
      invoke("agent-1", "Read")

      assert %{recent: recent} = Signals.peek(LoopDetected, "agent-1")
      assert length(recent) <= 3
    end

    @tag signals: [LoopDetected], sink: Collector
    test "a replayed event is not folded twice" do
      event =
        Event.new("agent.tool.invoked", subject: "a", data: %{"tool" => "Read"})
        |> Event.with_position(1)

      Signals.emit_event(event)
      sync()
      Signals.emit_event(event)
      sync()
      Signals.emit_event(event)
      sync()

      # Three deliveries, one distinct position — a loop needs three real events.
      assert Collector.emissions() == []
      assert %{recent: ["Read"]} = Signals.peek(LoopDetected, "a")
    end

    @tag signals: [LoopDetected], sink: Collector
    test "distinct positions are folded normally" do
      for position <- 1..3 do
        Event.new("agent.tool.invoked", subject: "a", data: %{"tool" => "Read"})
        |> Event.with_position(position)
        |> Signals.emit_event()

        sync()
      end

      assert [_] = Collector.emissions_of("loop_detected")
    end

    @tag signals: [LoopDetected], store: Signals.Store.Null, sink: Collector
    test "the null store still works, it just forgets" do
      for _ <- 1..3, do: invoke("agent-1", "Read")

      assert [_] = Collector.emissions_of("loop_detected")
    end
  end

  describe "resilience" do
    @tag signals: [LoopDetected]
    test "a stray message does not kill an accumulator" do
      invoke("agent-1", "Read")
      pid = Signals.Registry.whereis(LoopDetected, "agent-1")

      send(pid, {:DOWN, make_ref(), :process, self(), :normal})
      send(pid, :nonsense)
      :sys.get_state(pid)

      assert Process.alive?(pid)
    end

    @tag signals: [LoopDetected]
    test "an event with no data does not crash the fold" do
      emit("agent.tool.invoked", subject: "agent-1")

      assert Process.alive?(Signals.Registry.whereis(LoopDetected, "agent-1"))
    end
  end

  describe "the use macro" do
    defmodule Bare do
      @moduledoc false
      use Signals.Signal
    end

    test "derives a name from the module" do
      assert Bare.name() == "bare"
    end

    test "defaults to watching nothing and concluding nothing" do
      assert Bare.topics() == []
      refute Bare.ready?(Bare.init("k"), :event)
    end

    test "handle_info leaves state untouched by default" do
      state = Bare.init("k")
      assert Bare.handle_info(:anything, state) == state
    end

    test "signal?/1 recognises it" do
      assert Signals.Signal.signal?(Bare)
      refute Signals.Signal.signal?(Enum)
    end
  end
end
