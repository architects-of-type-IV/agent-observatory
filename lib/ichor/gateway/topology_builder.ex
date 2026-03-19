defmodule Ichor.Gateway.TopologyBuilder do
  @moduledoc """
  Sole publisher on the "gateway:topology" PubSub topic.

  Fleet Command LiveView subscribes to this topic in mount/3.
  Direct ETS reads from LiveView are prohibited (FR-8.13, ADR-016).
  """

  use GenServer

  require Logger

  alias Ichor.Mesh.CausalDAG

  @sweep_interval :timer.hours(1)
  @stale_ttl_seconds 7_200

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe_to_session(session_id) do
    GenServer.cast(__MODULE__, {:subscribe, session_id})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    schedule_sweep()
    {:ok, %{sessions: MapSet.new(), session_last_active: %{}}}
  end

  @impl true
  def handle_cast({:subscribe, session_id}, state) do
    if MapSet.member?(state.sessions, session_id) do
      {:noreply, state}
    else
      Phoenix.PubSub.subscribe(Ichor.PubSub, "session:dag:#{session_id}")
      updated_sessions = MapSet.put(state.sessions, session_id)
      {:noreply, %{state | sessions: updated_sessions}}
    end
  end

  @impl true
  def handle_info(%{event: "dag_delta", session_id: session_id}, state) do
    state = put_in(state.session_last_active[session_id], System.monotonic_time(:second))

    case CausalDAG.get_session_dag(session_id) do
      {:ok, node_map} ->
        Ichor.Signals.emit(:topology_snapshot, build_topology(node_map))
        {:noreply, state}

      {:error, :session_not_found} ->
        Logger.debug("TopologyBuilder: session not found for session_id=#{session_id}")
        {:noreply, state}
    end
  end

  def handle_info(:sweep, state) do
    cutoff = System.monotonic_time(:second) - @stale_ttl_seconds

    stale_sids =
      state.session_last_active
      |> Enum.filter(fn {_sid, ts} -> ts < cutoff end)
      |> Enum.map(&elem(&1, 0))

    # Unsubscribe from stale sessions
    Enum.each(stale_sids, fn sid ->
      Phoenix.PubSub.unsubscribe(Ichor.PubSub, "session:dag:#{sid}")
    end)

    new_sessions = Enum.reduce(stale_sids, state.sessions, &MapSet.delete(&2, &1))
    new_last_active = Map.drop(state.session_last_active, stale_sids)

    schedule_sweep()
    {:noreply, %{state | sessions: new_sessions, session_last_active: new_last_active}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp build_topology(node_map) do
    nodes =
      Enum.map(node_map, fn {_trace_id, node} ->
        %{
          trace_id: node.trace_id,
          agent_id: node.agent_id,
          state: node.action_status || :idle,
          x: nil,
          y: nil
        }
      end)

    edges =
      Enum.flat_map(node_map, fn {_trace_id, node} ->
        Enum.map(node.children, fn child_id ->
          %{
            from: node.trace_id,
            to: child_id,
            traffic_volume: 0,
            latency_ms: 0,
            status: "active",
            from_x: nil,
            from_y: nil,
            to_x: nil,
            to_y: nil
          }
        end)
      end)

    %{nodes: nodes, edges: edges}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end
end
