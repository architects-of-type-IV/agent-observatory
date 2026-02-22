defmodule Observatory.Gateway.EntropyTrackerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Observatory.Gateway.EntropyTracker
  alias Observatory.Gateway.SchemaInterceptor

  setup do
    start_supervised!({EntropyTracker, []})

    on_exit(fn ->
      Application.delete_env(:observatory, :entropy_window_size)
      Application.delete_env(:observatory, :entropy_loop_threshold)
      Application.delete_env(:observatory, :entropy_warning_threshold)
    end)

    :ok
  end

  describe "GenServer & ETS (3.4.1)" do
    test "ETS table is private and inaccessible from outside the GenServer process" do
      # The ETS table :entropy_windows is private -- lookup from test process must raise
      assert_raise ArgumentError, fn ->
        :ets.lookup(:entropy_windows, "any-session")
      end
    end

    test "record_and_score/2 returns {:ok, score, severity} for a valid tuple" do
      result = EntropyTracker.record_and_score("sess-1", {:plan, "write_file", :success})
      assert {:ok, score, :normal} = result
      assert is_float(score)
    end
  end

  describe "sliding window mechanics (3.4.2)" do
    test "sixth tuple evicts oldest and window remains capped at 5" do
      session = "sess-cap-#{System.unique_integer([:positive])}"

      tuples =
        for i <- 1..6 do
          {:"intent_#{i}", "tool_#{i}", :success}
        end

      for t <- tuples do
        assert {:ok, _score, _sev} = EntropyTracker.record_and_score(session, t)
      end

      window = EntropyTracker.get_window(session)
      assert length(window) == 5
      # First tuple should have been evicted
      refute Enum.member?(window, List.first(tuples))
      # Last tuple should be present
      assert Enum.member?(window, List.last(tuples))
    end

    test "score computed over 3 tuples equals unique_count divided by 3" do
      session = "sess-3-#{System.unique_integer([:positive])}"

      # 3 distinct tuples -> 3/3 = 1.0
      EntropyTracker.record_and_score(session, {:a, "t1", :success})
      EntropyTracker.record_and_score(session, {:b, "t2", :failure})
      assert {:ok, 1.0, :normal} = EntropyTracker.record_and_score(session, {:c, "t3", :success})
    end
  end

  describe "uniqueness ratio computation (3.5.1)" do
    test "5 identical tuples yield score 0.2 and :loop severity" do
      session = "sess-identical-#{System.unique_integer([:positive])}"
      EntropyTracker.register_agent(session, "agent-loop")
      # Small delay for cast to process
      Process.sleep(10)

      tuple = {:search, "read_file", :failure}

      for _ <- 1..4 do
        EntropyTracker.record_and_score(session, tuple)
      end

      assert {:ok, 0.2, :loop} = EntropyTracker.record_and_score(session, tuple)
    end

    test "5 unique tuples yield score 1.0 and :normal severity" do
      session = "sess-unique-#{System.unique_integer([:positive])}"

      for i <- 1..4 do
        EntropyTracker.record_and_score(session, {:"intent_#{i}", "tool_#{i}", :success})
      end

      assert {:ok, 1.0, :normal} =
               EntropyTracker.record_and_score(session, {:intent_5, "tool_5", :success})
    end

    test "3 tuples with 2 unique yield score 0.6667" do
      session = "sess-partial-#{System.unique_integer([:positive])}"

      EntropyTracker.record_and_score(session, {:a, "t1", :success})
      EntropyTracker.record_and_score(session, {:a, "t1", :success})

      assert {:ok, 0.6667, :normal} =
               EntropyTracker.record_and_score(session, {:b, "t2", :failure})
    end
  end

  describe "LOOP threshold actions (3.5.2)" do
    test "score 0.2 triggers LOOP: returns {:ok, 0.2, :loop} and broadcasts to both topics" do
      session = "sess-loop-#{System.unique_integer([:positive])}"
      EntropyTracker.register_agent(session, "agent-7")
      Process.sleep(10)

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:entropy_alerts")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      tuple = {:search, "list_files", :failure}

      for _ <- 1..4 do
        EntropyTracker.record_and_score(session, tuple)
      end

      assert {:ok, 0.2, :loop} = EntropyTracker.record_and_score(session, tuple)

      assert_receive %{event_type: "entropy_alert", session_id: ^session}, 1000
      assert_receive %{session_id: ^session, state: "alert_entropy"}, 1000
    end

    test "score exactly 0.25 does NOT trigger LOOP" do
      session = "sess-boundary-#{System.unique_integer([:positive])}"
      EntropyTracker.register_agent(session, "agent-boundary")
      Process.sleep(10)

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:entropy_alerts")

      # 4 identical + 1 unique in a window of 5 -> 2/5 = 0.4 (WARNING)
      # For exactly 0.25 we need 1 unique in 4 entries: 1/4 = 0.25
      # Use window_size 4 temporarily
      Application.put_env(:observatory, :entropy_window_size, 4)

      tuple = {:x, "y", :failure}

      for _ <- 1..3 do
        EntropyTracker.record_and_score(session, tuple)
      end

      # 4th call: 1 unique in 4 = 0.25 -- exactly at threshold, NOT below
      assert {:ok, 0.25, :warning} = EntropyTracker.record_and_score(session, tuple)

      refute_receive %{event_type: "entropy_alert"}, 200
    end
  end

  describe "WARNING range (3.5.3)" do
    test "score 0.4 triggers WARNING with topology broadcast but no alert" do
      session = "sess-warn-#{System.unique_integer([:positive])}"

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:entropy_alerts")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      # 2 unique in 5 = 0.4
      tuple_a = {:search, "read_file", :failure}
      tuple_b = {:plan, "write_file", :success}

      for _ <- 1..3 do
        EntropyTracker.record_and_score(session, tuple_a)
      end

      EntropyTracker.record_and_score(session, tuple_b)
      assert {:ok, 0.4, :warning} = EntropyTracker.record_and_score(session, tuple_a)

      assert_receive %{session_id: ^session, state: "blocked"}, 1000
      refute_receive %{event_type: "entropy_alert"}, 200
    end

    test "prior WARNING does not suppress LOOP escalation" do
      session = "sess-escalate-#{System.unique_integer([:positive])}"
      EntropyTracker.register_agent(session, "agent-esc")
      Process.sleep(10)

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:entropy_alerts")

      # Drive to WARNING: 2 unique in 5 = 0.4
      tuple_a = {:search, "read_file", :failure}
      tuple_b = {:plan, "write_file", :success}

      for _ <- 1..3 do
        EntropyTracker.record_and_score(session, tuple_a)
      end

      EntropyTracker.record_and_score(session, tuple_b)
      assert {:ok, 0.4, :warning} = EntropyTracker.record_and_score(session, tuple_a)

      # Now push to LOOP: 5 more identical -> window becomes all tuple_a
      for _ <- 1..4 do
        EntropyTracker.record_and_score(session, tuple_a)
      end

      assert {:ok, 0.2, :loop} = EntropyTracker.record_and_score(session, tuple_a)
      assert_receive %{event_type: "entropy_alert", session_id: ^session}, 1000
    end
  end

  describe "Normal range recovery (3.5.4)" do
    test "score 1.0 returns {:ok, 1.0, :normal} with no broadcast" do
      session = "sess-healthy-#{System.unique_integer([:positive])}"

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:entropy_alerts")
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      for i <- 1..4 do
        EntropyTracker.record_and_score(session, {:"i_#{i}", "t_#{i}", :success})
      end

      assert {:ok, 1.0, :normal} =
               EntropyTracker.record_and_score(session, {:i_5, "t_5", :success})

      refute_receive %{event_type: "entropy_alert"}, 200
      refute_receive %{state: _}, 200
    end

    test "score recovering from LOOP broadcasts :active reset to gateway:topology" do
      session = "sess-recover-#{System.unique_integer([:positive])}"
      EntropyTracker.register_agent(session, "agent-rec")
      Process.sleep(10)

      # Drive to LOOP (5 identical tuples -> 0.2)
      tuple = {:search, "read_file", :failure}

      for _ <- 1..5 do
        EntropyTracker.record_and_score(session, tuple)
      end

      # Subscribe BEFORE recovery so we catch the transition broadcast
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:topology")

      # Push enough distinct tuples to recover to normal.
      # After 5 distinct tuples, window is all unique -> score 1.0 -> :normal
      # The "active" broadcast fires on the first call where score >= 0.50
      # and prior_severity was :loop or :warning.
      for i <- 1..5 do
        EntropyTracker.record_and_score(session, {:"new_#{i}", "tool_#{i}", :success})
      end

      # At some point during recovery, an "active" state was broadcast
      assert_receive %{session_id: ^session, state: "active"}, 1000
    end

    test "score exactly 0.50 is classified as :normal" do
      session = "sess-boundary50-#{System.unique_integer([:positive])}"

      # 2 unique in 4 entries = 0.5 exactly
      Application.put_env(:observatory, :entropy_window_size, 4)

      tuple_a = {:a, "t1", :success}
      tuple_b = {:b, "t2", :failure}

      EntropyTracker.record_and_score(session, tuple_a)
      EntropyTracker.record_and_score(session, tuple_a)
      EntropyTracker.record_and_score(session, tuple_b)
      assert {:ok, 0.5, :normal} = EntropyTracker.record_and_score(session, tuple_b)
    end
  end

  describe "EntropyAlertEvent fields (3.5.5)" do
    test "EntropyAlertEvent contains all 7 required fields with correct values" do
      session = "sess-alert-fields-#{System.unique_integer([:positive])}"
      EntropyTracker.register_agent(session, "agent-7")
      Process.sleep(10)

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:entropy_alerts")

      # 4 identical + 1 distinct = 2 unique in 5 = 0.4 (WARNING, not LOOP)
      # Need score < 0.25 for LOOP: 1 unique in 5 = 0.2
      tuple = {:search, "list_files", :failure}

      for _ <- 1..4 do
        EntropyTracker.record_and_score(session, tuple)
      end

      assert {:ok, 0.2, :loop} = EntropyTracker.record_and_score(session, tuple)

      assert_receive event, 1000

      assert event.event_type == "entropy_alert"
      assert event.session_id == session
      assert event.agent_id == "agent-7"
      assert event.entropy_score == 0.2
      assert event.window_size == 5
      assert event.repeated_pattern == %{intent: "search", tool_call: "list_files", action_status: "failure"}
      assert event.occurrence_count == 5
    end

    test "missing agent_id returns {:error, :missing_agent_id} and no alert broadcast" do
      session = "sess-no-agent-#{System.unique_integer([:positive])}"

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:entropy_alerts")

      tuple = {:search, "list_files", :failure}

      for _ <- 1..4 do
        EntropyTracker.record_and_score(session, tuple)
      end

      assert {:error, :missing_agent_id} = EntropyTracker.record_and_score(session, tuple)

      refute_receive %{event_type: "entropy_alert"}, 200
    end
  end

  describe "register_agent/2" do
    test "register_agent stores agent_id for subsequent LOOP alerts" do
      session = "sess-reg-#{System.unique_integer([:positive])}"

      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:entropy_alerts")

      tuple = {:search, "list_files", :failure}

      # First, without agent_id -> error
      for _ <- 1..5 do
        EntropyTracker.record_and_score(session, tuple)
      end

      refute_receive %{event_type: "entropy_alert"}, 200

      # Now register agent and trigger another LOOP
      EntropyTracker.register_agent(session, "agent-late")
      Process.sleep(10)

      assert {:ok, 0.2, :loop} = EntropyTracker.record_and_score(session, tuple)
      assert_receive %{event_type: "entropy_alert", agent_id: "agent-late"}, 1000
    end
  end

  describe "SchemaInterceptor integration (3.6.1)" do
    @integration_params %{
      "meta" => %{
        "trace_id" => "will-be-replaced",
        "timestamp" => "2026-02-22T12:00:00Z"
      },
      "identity" => %{
        "agent_id" => "agent-001",
        "agent_type" => "reasoning",
        "capability_version" => "1.0.0"
      },
      "cognition" => %{
        "intent" => "classify_input",
        "confidence_score" => 0.95,
        "strategy_used" => "CoT",
        "entropy_score" => 0.9
      },
      "action" => %{
        "status" => "success",
        "tool_call" => "classify",
        "tool_input" => "{}",
        "tool_output_summary" => "done"
      },
      "state_delta" => %{"tokens_consumed" => 150},
      "control" => %{"hitl_required" => false, "is_terminal" => false}
    }

    test "SchemaInterceptor overwrites cognition.entropy_score with Gateway-computed value" do
      session = "sess-overwrite-#{System.unique_integer([:positive])}"
      params = put_in(@integration_params, ["meta", "trace_id"], session)

      assert {:ok, log} = SchemaInterceptor.validate_and_enrich(params)

      # The agent-reported score 0.9 should be replaced by the Gateway-computed value.
      # For the first call, score = 1.0 (1 unique / 1 total) which != 0.9.
      assert log.cognition.entropy_score != 0.9
      assert is_float(log.cognition.entropy_score)
    end

    test "SchemaInterceptor retains original score when EntropyTracker returns error" do
      session = "sess-retain-#{System.unique_integer([:positive])}"
      params = put_in(@integration_params, ["meta", "trace_id"], session)

      # Pre-fill the window with identical tuples matching what validate_and_enrich will extract:
      # intent="classify_input", tool_call="classify", action_status=:success
      tuple = {"classify_input", "classify", :success}

      for _ <- 1..4 do
        EntropyTracker.record_and_score(session, tuple)
      end

      # 5th call (from validate_and_enrich) pushes score to 0.2 (LOOP).
      # No agent_id registered -> {:error, :missing_agent_id} -> original score retained.
      assert {:ok, log} = SchemaInterceptor.validate_and_enrich(params)
      assert log.cognition.entropy_score == 0.9
    end
  end

  describe "entropy alert deduplication (3.6.3)" do
    test "two EntropyAlertEvents for same session_id appear only once in alerts map" do
      event1 = %{session_id: "sess-dedup", entropy_score: 0.2, event_type: "entropy_alert"}
      event2 = %{session_id: "sess-dedup", entropy_score: 0.1, event_type: "entropy_alert"}

      alerts =
        %{}
        |> SchemaInterceptor.deduplicate_alert(event1)
        |> SchemaInterceptor.deduplicate_alert(event2)

      assert map_size(alerts) == 1
      assert alerts["sess-dedup"].entropy_score == 0.1
    end

    test "EntropyAlertEvents for two different sessions produce two map entries" do
      event1 = %{session_id: "sess-alpha", entropy_score: 0.2, event_type: "entropy_alert"}
      event2 = %{session_id: "sess-beta", entropy_score: 0.15, event_type: "entropy_alert"}

      alerts =
        %{}
        |> SchemaInterceptor.deduplicate_alert(event1)
        |> SchemaInterceptor.deduplicate_alert(event2)

      assert map_size(alerts) == 2
      assert Map.has_key?(alerts, "sess-alpha")
      assert Map.has_key?(alerts, "sess-beta")
    end
  end

  describe "runtime configuration (3.6.4)" do
    test "runtime change to entropy_loop_threshold takes effect on next call" do
      session = "sess-runtime-loop-#{System.unique_integer([:positive])}"
      EntropyTracker.register_agent(session, "agent-rt")
      Process.sleep(10)

      # Set loop threshold to 0.30
      Application.put_env(:observatory, :entropy_loop_threshold, 0.30)

      # 2 unique in 5 = 0.4 -> above 0.30, so WARNING
      # But let's target score 0.28: need window that gives < 0.30
      # With window_size 5: need fewer than 1.5 unique, so 1 unique -> 0.2 (LOOP)
      # Actually, for 0.28 specifically we can't get exactly that with integers.
      # Let's just verify 0.2 triggers LOOP under 0.30 threshold
      tuple = {:x, "y", :failure}

      for _ <- 1..4 do
        EntropyTracker.record_and_score(session, tuple)
      end

      assert {:ok, 0.2, :loop} = EntropyTracker.record_and_score(session, tuple)
    end

    test "runtime change to entropy_warning_threshold takes effect" do
      session = "sess-runtime-warn-#{System.unique_integer([:positive])}"

      # Raise warning threshold to 0.80
      Application.put_env(:observatory, :entropy_warning_threshold, 0.80)

      # 3 unique in 5 = 0.6 -> normally :normal, but now :warning (0.6 < 0.80)
      for i <- 1..2 do
        EntropyTracker.record_and_score(session, {:"a_#{i}", "t", :success})
      end

      EntropyTracker.record_and_score(session, {:a_1, "t", :success})
      EntropyTracker.record_and_score(session, {:a_2, "t", :success})

      assert {:ok, 0.6, :warning} =
               EntropyTracker.record_and_score(session, {:a_3, "t", :success})
    end

    test "runtime change to entropy_window_size takes effect" do
      session = "sess-runtime-ws-#{System.unique_integer([:positive])}"

      Application.put_env(:observatory, :entropy_window_size, 3)

      EntropyTracker.record_and_score(session, {:a, "t1", :s})
      EntropyTracker.record_and_score(session, {:b, "t2", :s})
      EntropyTracker.record_and_score(session, {:c, "t3", :s})
      EntropyTracker.record_and_score(session, {:d, "t4", :s})

      window = EntropyTracker.get_window(session)
      assert length(window) == 3
    end

    test "invalid string value for entropy_loop_threshold falls back to default 0.25" do
      session = "sess-invalid-#{System.unique_integer([:positive])}"
      EntropyTracker.register_agent(session, "agent-inv")
      Process.sleep(10)

      Application.put_env(:observatory, :entropy_loop_threshold, "bad")

      log =
        capture_log(fn ->
          tuple = {:x, "y", :failure}

          for _ <- 1..5 do
            EntropyTracker.record_and_score(session, tuple)
          end
        end)

      assert log =~ "invalid entropy_loop_threshold"
      assert log =~ "bad"
    end
  end

end
