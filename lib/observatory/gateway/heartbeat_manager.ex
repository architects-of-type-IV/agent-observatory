defmodule Observatory.Gateway.HeartbeatManager do
  @moduledoc """
  Tracks agent liveness via periodic heartbeats. Agents that fail to ping
  within `@eviction_threshold_seconds` are evicted and removed from the
  CapabilityMap.
  """

  use GenServer

  require Logger

  @eviction_threshold_seconds 90
  @check_interval_ms 30_000

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Record a heartbeat for `agent_id` within `cluster_id`."
  def record_heartbeat(agent_id, cluster_id) do
    GenServer.call(__MODULE__, {:heartbeat, agent_id, cluster_id})
  end

  @doc "Returns all tracked agents as a map of `%{agent_id => %{last_seen, cluster_id}}`."
  def list_agents do
    GenServer.call(__MODULE__, :list_agents)
  end

  @doc "Returns agents past the eviction threshold that haven't been evicted yet."
  def list_zombies do
    GenServer.call(__MODULE__, :list_zombies)
  end

  # ── Server Callbacks ────────────────────────────────────────────────

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

  def handle_call(:list_agents, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:list_zombies, _from, state) do
    now = DateTime.utc_now()

    zombies =
      state
      |> Enum.filter(fn {_id, %{last_seen: last_seen}} ->
        DateTime.diff(now, last_seen, :second) > @eviction_threshold_seconds
      end)
      |> Map.new()

    {:reply, zombies, state}
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
      Observatory.Gateway.CapabilityMap.remove_agent(agent_id)
      Logger.info("Evicted stale agent #{agent_id}")
    end)

    {:noreply, Map.drop(state, evicted_ids)}
  end
end
