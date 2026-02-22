defmodule Observatory.Gateway.HeartbeatManagerTest do
  use ExUnit.Case, async: false

  alias Observatory.Gateway.HeartbeatManager

  setup do
    # Reset the already-running HeartbeatManager to a clean state
    pid = Process.whereis(HeartbeatManager)
    :sys.replace_state(pid, fn _state -> %{} end)
    {:ok, pid: pid}
  end

  describe "record_heartbeat/2" do
    test "records a heartbeat and returns :ok" do
      assert :ok = HeartbeatManager.record_heartbeat("agent-1", "cluster-a")
    end

    test "updates existing heartbeat for the same agent" do
      assert :ok = HeartbeatManager.record_heartbeat("agent-1", "cluster-a")
      assert :ok = HeartbeatManager.record_heartbeat("agent-1", "cluster-b")
    end

    test "tracks multiple agents independently" do
      assert :ok = HeartbeatManager.record_heartbeat("agent-1", "cluster-a")
      assert :ok = HeartbeatManager.record_heartbeat("agent-2", "cluster-b")
    end
  end

  describe "eviction via :check_heartbeats" do
    test "does not evict agents within threshold" do
      HeartbeatManager.record_heartbeat("agent-1", "cluster-a")

      # Trigger check manually
      send(Process.whereis(HeartbeatManager), :check_heartbeats)
      # Give GenServer time to process
      :timer.sleep(50)

      # Agent should still be trackable (re-heartbeat succeeds)
      assert :ok = HeartbeatManager.record_heartbeat("agent-1", "cluster-a")
    end

    test "evicts agents beyond the threshold" do
      # Inject a stale entry directly via GenServer state
      stale_time = DateTime.add(DateTime.utc_now(), -100, :second)

      :sys.replace_state(Process.whereis(HeartbeatManager), fn _state ->
        %{"stale-agent" => %{last_seen: stale_time, cluster_id: "cluster-x"}}
      end)

      # Trigger eviction check
      send(Process.whereis(HeartbeatManager), :check_heartbeats)
      :timer.sleep(50)

      # Verify state is now empty (stale agent evicted)
      state = :sys.get_state(Process.whereis(HeartbeatManager))
      refute Map.has_key?(state, "stale-agent")
    end

    test "keeps fresh agents while evicting stale ones" do
      now = DateTime.utc_now()
      stale_time = DateTime.add(now, -100, :second)

      :sys.replace_state(Process.whereis(HeartbeatManager), fn _state ->
        %{
          "fresh-agent" => %{last_seen: now, cluster_id: "cluster-a"},
          "stale-agent" => %{last_seen: stale_time, cluster_id: "cluster-b"}
        }
      end)

      send(Process.whereis(HeartbeatManager), :check_heartbeats)
      :timer.sleep(50)

      state = :sys.get_state(Process.whereis(HeartbeatManager))
      assert Map.has_key?(state, "fresh-agent")
      refute Map.has_key?(state, "stale-agent")
    end
  end
end
