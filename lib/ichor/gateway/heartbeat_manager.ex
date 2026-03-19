defmodule Ichor.Gateway.HeartbeatManager do
  @moduledoc """
  Tracks agent liveness via periodic heartbeats. Agents that fail to ping
  within `@eviction_threshold_seconds` are evicted.
  """

  use GenServer

  require Logger

  alias Ichor.Signals

  @eviction_threshold_seconds 90
  @check_interval_ms 30_000

  @doc "Start the HeartbeatManager GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Record a heartbeat for `agent_id` within `cluster_id`."
  @spec record_heartbeat(String.t(), String.t()) :: :ok
  def record_heartbeat(agent_id, cluster_id) do
    GenServer.call(__MODULE__, {:heartbeat, agent_id, cluster_id})
  end

  @impl true
  def init(_opts) do
    :timer.send_interval(@check_interval_ms, :check_heartbeats)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:heartbeat, agent_id, cluster_id}, _from, state) do
    entry = %{last_seen: DateTime.utc_now(), cluster_id: cluster_id}
    {:reply, :ok, Map.put(state, agent_id, entry)}
  end

  @impl true
  def handle_info(:check_heartbeats, state) do
    now = DateTime.utc_now()

    evicted_ids =
      state
      |> Enum.filter(fn {_id, %{last_seen: last_seen}} ->
        DateTime.diff(now, last_seen, :second) > @eviction_threshold_seconds
      end)
      |> Enum.map(fn {id, _entry} -> id end)

    Enum.each(evicted_ids, fn agent_id ->
      Signals.emit(:agent_evicted, %{session_id: agent_id})
      Logger.info("Evicted stale agent #{agent_id}")
    end)

    {:noreply, Map.drop(state, evicted_ids)}
  end
end
