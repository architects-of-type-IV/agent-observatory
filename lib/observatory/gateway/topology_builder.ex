defmodule Observatory.Gateway.TopologyBuilder do
  @moduledoc """
  Sole publisher on the "gateway:topology" PubSub topic.

  Fleet Command LiveView subscribes to this topic in mount/3.
  Direct ETS reads from LiveView are prohibited (FR-8.13, ADR-016).
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe_to_session(session_id) do
    GenServer.cast(__MODULE__, {:subscribe, session_id})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{sessions: MapSet.new()}}
  end

  @impl true
  def handle_cast({:subscribe, session_id}, state) do
    if MapSet.member?(state.sessions, session_id) do
      {:noreply, state}
    else
      Phoenix.PubSub.subscribe(Observatory.PubSub, "session:dag:#{session_id}")
      updated_sessions = MapSet.put(state.sessions, session_id)
      {:noreply, %{state | sessions: updated_sessions}}
    end
  end

  @impl true
  def handle_info(%{event: "dag_delta", session_id: session_id}, state) do
    case Observatory.Mesh.CausalDAG.get_session_dag(session_id) do
      {:ok, node_map} ->
        # Derive nodes list
        nodes =
          node_map
          |> Enum.map(fn {_trace_id, node} ->
            %{
              trace_id: node.trace_id,
              agent_id: node.agent_id,
              state: node.action_status || :idle,
              x: nil,
              y: nil
            }
          end)

        # Derive edges list
        edges =
          node_map
          |> Enum.flat_map(fn {_trace_id, node} ->
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

        # Broadcast to gateway:topology
        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "gateway:topology",
          %{nodes: nodes, edges: edges}
        )

        {:noreply, state}

      {:error, :session_not_found} ->
        Logger.debug("TopologyBuilder: session not found for session_id=#{session_id}")
        {:noreply, state}
    end
  end
end
