defmodule FleetAnalysis.HealthTest do
  use ExUnit.Case, async: false

  import FleetAnalysis.TestEvents

  alias FleetAnalysis.Health

  doctest FleetAnalysis.Health

  setup do
    on_exit(fn ->
      for key <- [
            :stuck_after_sec,
            :loop_window,
            :loop_min_repeats,
            :failure_rate_warning,
            :failure_rate_critical
          ] do
        Application.delete_env(:fleet_analysis, key)
      end
    end)

    :ok
  end

  describe "with no events" do
    test "health is unknown, not healthy" do
      # An agent nobody has heard from is not the same as a well one.
      assert %{health: :unknown, issues: []} = result = Health.compute([], now())
      assert result.failure_rate == 0.0
    end

    test "is not reported as stuck" do
      assert %{stuck?: false, loops: []} = Health.compute([], now())
    end
  end

  describe "stuck detection" do
    test "recent activity is healthy" do
      events = [event(inserted_at: ago(5))]

      assert %{health: :healthy, stuck?: false} = Health.compute(events, now())
    end

    test "silence past the threshold is critical" do
      events = [event(inserted_at: ago(120))]

      assert %{health: :critical, stuck?: true} = Health.compute(events, now())
    end

    test "the issue carries the last event seen" do
      last = event(inserted_at: ago(120), tool_name: "Bash")

      assert %{issues: issues} = Health.compute([last], now())
      assert {:stuck, ^last} = List.keyfind(issues, :stuck, 0)
    end

    test "staleness is measured from the newest event, not the first in the list" do
      events = [event(inserted_at: ago(600)), event(inserted_at: ago(1))]

      assert %{stuck?: false} = Health.compute(events, now())
    end

    test "exactly at the threshold is not yet stuck" do
      assert %{stuck?: false} = Health.compute([event(inserted_at: ago(60))], now())
      assert %{stuck?: true} = Health.compute([event(inserted_at: ago(61))], now())
    end

    test "honours a configured threshold" do
      Application.put_env(:fleet_analysis, :stuck_after_sec, 10)

      assert %{stuck?: true} = Health.compute([event(inserted_at: ago(30))], now())
    end
  end

  describe "loop detection" do
    test "three consecutive calls to the same tool is a loop" do
      assert %{loops: [%{tool: "Read", count: 3}], health: :critical} =
               Health.compute(tool_run("Read", 3), now())
    end

    test "two consecutive calls is not" do
      assert %{loops: [], health: :healthy} = Health.compute(tool_run("Read", 2), now())
    end

    test "alternating tools is not a loop" do
      events = [
        event(tool_name: "Read"),
        event(tool_name: "Bash"),
        event(tool_name: "Read"),
        event(tool_name: "Bash")
      ]

      assert %{loops: []} = Health.compute(events, now())
    end

    test "only PreToolUse events count" do
      events = [
        event(tool_name: "Read", hook_event_type: :PreToolUse),
        event(tool_name: "Read", hook_event_type: :PostToolUse),
        event(tool_name: "Read", hook_event_type: :PostToolUse)
      ]

      assert %{loops: []} = Health.compute(events, now())
    end

    test "only the recent window is considered" do
      Application.put_env(:fleet_analysis, :loop_window, 2)

      assert %{loops: []} = Health.compute(tool_run("Read", 3), now())
    end

    test "honours a configured repeat count" do
      Application.put_env(:fleet_analysis, :loop_min_repeats, 2)

      assert %{loops: [%{count: 2}]} = Health.compute(tool_run("Read", 2), now())
    end

    test "the issue names the looping tool" do
      assert %{issues: issues} = Health.compute(tool_run("Bash", 3), now())
      assert {:looping, [%{tool: "Bash"}]} = List.keyfind(issues, :looping, 0)
    end
  end

  describe "failure_rate/1" do
    test "no tool events scores zero" do
      assert Health.failure_rate([]) == 0.0
      assert Health.failure_rate([event(hook_event_type: :PreToolUse)]) == 0.0
    end

    test "all successes scores zero" do
      events = for _ <- 1..3, do: event(hook_event_type: :PostToolUse)

      assert Health.failure_rate(events) == 0.0
    end

    test "all failures scores one" do
      events = for _ <- 1..3, do: event(hook_event_type: :PostToolUseFailure)

      assert Health.failure_rate(events) == 1.0
    end

    test "a mix rounds to two places" do
      events = [
        event(hook_event_type: :PostToolUseFailure),
        event(hook_event_type: :PostToolUse),
        event(hook_event_type: :PostToolUse)
      ]

      assert Health.failure_rate(events) == 0.33
    end

    test "PreToolUse events are excluded from the denominator" do
      events = [
        event(hook_event_type: :PreToolUse),
        event(hook_event_type: :PostToolUseFailure)
      ]

      assert Health.failure_rate(events) == 1.0
    end
  end

  describe "health classification" do
    test "a moderate failure rate is a warning" do
      events =
        [event(hook_event_type: :PostToolUseFailure)] ++
          for(_ <- 1..2, do: event(hook_event_type: :PostToolUse))

      assert %{health: :warning, failure_rate: 0.33} = Health.compute(events, now())
    end

    test "a low failure rate stays healthy" do
      events =
        [event(hook_event_type: :PostToolUseFailure)] ++
          for(_ <- 1..9, do: event(hook_event_type: :PostToolUse))

      assert %{health: :healthy} = Health.compute(events, now())
    end

    test "a high failure rate raises an issue" do
      events =
        for(_ <- 1..3, do: event(hook_event_type: :PostToolUseFailure)) ++
          [event(hook_event_type: :PostToolUse)]

      assert %{issues: issues} = Health.compute(events, now())
      assert {:high_failure_rate, 0.75} = List.keyfind(issues, :high_failure_rate, 0)
    end

    test "stuck outranks a failure rate, since it will not resolve on its own" do
      events =
        for _ <- 1..4, do: event(hook_event_type: :PostToolUse, inserted_at: ago(300))

      assert %{health: :critical, stuck?: true} = Health.compute(events, now())
    end

    test "several issues are reported together" do
      events = tool_run("Read", 3, inserted_at: ago(300))

      assert %{issues: issues, health: :critical} = Health.compute(events, now())
      assert List.keyfind(issues, :stuck, 0)
      assert List.keyfind(issues, :looping, 0)
    end
  end

  describe "malformed events" do
    test "an event with no timestamp does not crash" do
      assert %{health: _} = Health.compute([%{session_id: "s1"}], now())
    end

    test "an event with no type does not crash" do
      assert Health.failure_rate([%{inserted_at: now()}]) == 0.0
    end

    test "an event with no tool name does not crash" do
      events = for _ <- 1..3, do: %{inserted_at: now(), hook_event_type: :PreToolUse}

      assert %{loops: [%{tool: nil, count: 3}]} = Health.compute(events, now())
    end
  end

  describe "compute/2 default clock" do
    test "defaults now to the current time" do
      assert %{health: :healthy} = Health.compute([event(inserted_at: DateTime.utc_now())])
    end
  end
end
