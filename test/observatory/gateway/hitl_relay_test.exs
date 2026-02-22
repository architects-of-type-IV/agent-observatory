defmodule Observatory.Gateway.HITLRelayTest do
  use ExUnit.Case, async: false

  alias Observatory.Gateway.HITLRelay

  setup do
    # Clean ETS buffer between tests
    :ets.delete_all_objects(:hitl_buffer)

    # Reset GenServer state by pausing then unpausing won't help;
    # we rely on unique session_ids per test instead
    :ok
  end

  describe "pause/4" do
    test "pauses a normal session" do
      sid = "pause-#{System.unique_integer([:positive])}"

      assert :ok = HITLRelay.pause(sid, "agent-1", "operator-1", "review needed")
      assert :paused = HITLRelay.session_status(sid)
    end

    test "returns already_paused when session is already paused" do
      sid = "already-paused-#{System.unique_integer([:positive])}"

      assert :ok = HITLRelay.pause(sid, "agent-1", "operator-1", "first pause")
      assert {:ok, :already_paused} = HITLRelay.pause(sid, "agent-1", "operator-1", "second pause")
    end

    test "broadcasts GateOpenEvent on pause" do
      sid = "broadcast-open-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Observatory.PubSub, "session:hitl:#{sid}")

      HITLRelay.pause(sid, "agent-1", "operator-1", "review")

      assert_receive {:hitl, %Observatory.Gateway.HITLEvents.GateOpenEvent{
        session_id: ^sid,
        agent_id: "agent-1",
        operator_id: "operator-1",
        reason: "review"
      }}
    end
  end

  describe "unpause/3" do
    test "returns not_paused for a normal session" do
      sid = "not-paused-#{System.unique_integer([:positive])}"

      assert {:ok, :not_paused} = HITLRelay.unpause(sid, "agent-1", "operator-1")
    end

    test "unpauses a paused session and returns flushed count of 0" do
      sid = "unpause-empty-#{System.unique_integer([:positive])}"

      HITLRelay.pause(sid, "agent-1", "operator-1", "check")
      assert {:ok, 0} = HITLRelay.unpause(sid, "agent-1", "operator-1")
      assert :normal = HITLRelay.session_status(sid)
    end

    test "flushes buffered messages in order on unpause" do
      sid = "flush-order-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:messages")

      HITLRelay.pause(sid, "agent-1", "operator-1", "hold")

      HITLRelay.buffer_message(sid, %{content: "msg-1", order: 1})
      # Small delay to ensure monotonic_time ordering
      Process.sleep(1)
      HITLRelay.buffer_message(sid, %{content: "msg-2", order: 2})
      Process.sleep(1)
      HITLRelay.buffer_message(sid, %{content: "msg-3", order: 3})

      assert {:ok, 3} = HITLRelay.unpause(sid, "agent-1", "operator-1")

      # Verify messages arrive in order
      assert_receive {:decision_log, %{content: "msg-1", order: 1}}
      assert_receive {:decision_log, %{content: "msg-2", order: 2}}
      assert_receive {:decision_log, %{content: "msg-3", order: 3}}
    end

    test "broadcasts GateCloseEvent on unpause" do
      sid = "broadcast-close-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Observatory.PubSub, "session:hitl:#{sid}")

      HITLRelay.pause(sid, "agent-1", "operator-1", "check")
      HITLRelay.unpause(sid, "agent-1", "operator-1")

      # Drain the GateOpenEvent first
      assert_receive {:hitl, %Observatory.Gateway.HITLEvents.GateOpenEvent{}}

      assert_receive {:hitl, %Observatory.Gateway.HITLEvents.GateCloseEvent{
        session_id: ^sid,
        agent_id: "agent-1",
        operator_id: "operator-1",
        flushed_count: 0
      }}
    end
  end

  describe "buffer_message/2" do
    test "buffers message when session is paused" do
      sid = "buffer-paused-#{System.unique_integer([:positive])}"

      HITLRelay.pause(sid, "agent-1", "operator-1", "hold")
      assert :ok = HITLRelay.buffer_message(sid, %{content: "buffered"})
    end

    test "returns pass_through when session is normal" do
      sid = "buffer-normal-#{System.unique_integer([:positive])}"

      assert :pass_through = HITLRelay.buffer_message(sid, %{content: "not buffered"})
    end

    test "returns pass_through for unknown session" do
      sid = "unknown-#{System.unique_integer([:positive])}"

      assert :pass_through = HITLRelay.buffer_message(sid, %{content: "nope"})
    end
  end

  describe "rewrite/3" do
    test "rewrites a buffered message payload" do
      sid = "rewrite-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:messages")

      HITLRelay.pause(sid, "agent-1", "operator-1", "edit")
      HITLRelay.buffer_message(sid, %{trace_id: "trace-42", payload: %{old: true}})

      assert :ok = HITLRelay.rewrite(sid, "trace-42", %{new: true})

      {:ok, 1} = HITLRelay.unpause(sid, "agent-1", "operator-1")

      assert_receive {:decision_log, %{trace_id: "trace-42", payload: %{new: true}}}
    end

    test "returns error when trace_id not found" do
      sid = "rewrite-miss-#{System.unique_integer([:positive])}"

      HITLRelay.pause(sid, "agent-1", "operator-1", "edit")

      assert {:error, :not_found} = HITLRelay.rewrite(sid, "nonexistent", %{})
    end
  end

  describe "inject/3" do
    test "injects a message into the buffer" do
      sid = "inject-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Observatory.PubSub, "gateway:messages")

      HITLRelay.pause(sid, "agent-1", "operator-1", "inject test")
      HITLRelay.inject(sid, "agent-1", %{injected_data: true})

      assert {:ok, 1} = HITLRelay.unpause(sid, "agent-1", "operator-1")

      assert_receive {:decision_log, %{agent_id: "agent-1", payload: %{injected_data: true}, injected: true}}
    end
  end

  describe "session_status/1" do
    test "returns :normal for unknown sessions" do
      sid = "unknown-status-#{System.unique_integer([:positive])}"

      assert :normal = HITLRelay.session_status(sid)
    end

    test "returns :paused for paused sessions" do
      sid = "status-paused-#{System.unique_integer([:positive])}"

      HITLRelay.pause(sid, "agent-1", "operator-1", "check")
      assert :paused = HITLRelay.session_status(sid)
    end

    test "returns :normal after unpause" do
      sid = "status-unpaused-#{System.unique_integer([:positive])}"

      HITLRelay.pause(sid, "agent-1", "operator-1", "check")
      HITLRelay.unpause(sid, "agent-1", "operator-1")
      assert :normal = HITLRelay.session_status(sid)
    end
  end
end
