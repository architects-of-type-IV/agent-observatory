defmodule Observatory.Mesh.CausalDAG do
  @moduledoc """
  ETS-backed directed acyclic graph maintaining one adjacency table per active session.

  Handles out-of-order arrival via a 30-second orphan buffer, enforces acyclicity via
  ancestor-chain traversal, and broadcasts incremental deltas over
  `session:dag:<session_id>` PubSub.

  See ADR-017 and FRD-008 for the full specification.
  """

  use GenServer

  defmodule Node do
    @moduledoc false
    defstruct trace_id: nil,
              parent_step_id: nil,
              agent_id: nil,
              intent: nil,
              confidence_score: nil,
              entropy_score: nil,
              action_status: nil,
              timestamp: nil,
              children: [],
              orphan: false
  end

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def insert(session_id, %Node{} = node) do
    GenServer.call(__MODULE__, {:insert, session_id, node})
  end

  def get_session_dag(session_id) do
    GenServer.call(__MODULE__, {:get_session_dag, session_id})
  end

  def get_children(session_id, trace_id) do
    GenServer.call(__MODULE__, {:get_children, session_id, trace_id})
  end

  def signal_terminal(session_id) do
    GenServer.cast(__MODULE__, {:terminal, session_id})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    :ets.new(:causal_dag_session_registry, [:set, :public, :named_table])
    :ets.new(:causal_dag_orphan_buffer, [:bag, :public, :named_table])
    Process.send_after(self(), :check_orphans, 5_000)
    {:ok, %{pending_deletions: %{}}}
  end

  @impl true
  def handle_call({:insert, session_id, node}, _from, state) do
    case validate_fields(node) do
      :ok ->
        table = ensure_session_table(session_id)
        do_insert(session_id, table, node, state)

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:get_session_dag, session_id}, _from, state) do
    case :ets.lookup(:causal_dag_session_registry, session_id) do
      [] ->
        {:reply, {:error, :session_not_found}, state}

      [{^session_id, _table_name}] ->
        table = :"dag_#{session_id}"
        entries = :ets.tab2list(table)
        node_map = Map.new(entries, fn {trace_id, node_val} -> {trace_id, node_val} end)
        {:reply, {:ok, node_map}, state}
    end
  end

  def handle_call({:get_children, session_id, trace_id}, _from, state) do
    case :ets.lookup(:causal_dag_session_registry, session_id) do
      [] ->
        {:reply, {:error, :not_found}, state}

      [{^session_id, _}] ->
        table = :"dag_#{session_id}"

        case :ets.lookup(table, trace_id) do
          [{^trace_id, found_node}] ->
            {:reply, {:ok, found_node.children}, state}

          [] ->
            {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_cast({:terminal, session_id}, state) do
    if Map.has_key?(state.pending_deletions, session_id) do
      {:noreply, state}
    else
      timer_ref = Process.send_after(self(), {:prune_session, session_id}, 300_000)
      updated = Map.put(state.pending_deletions, session_id, timer_ref)
      {:noreply, %{state | pending_deletions: updated}}
    end
  end

  @impl true
  def handle_info(:check_orphans, state) do
    now = System.monotonic_time(:millisecond)
    all_orphans = :ets.tab2list(:causal_dag_orphan_buffer)

    expired =
      Enum.filter(all_orphans, fn {_key, _node, inserted_at} ->
        now - inserted_at > 30_000
      end)

    Enum.each(expired, fn {{session_id, _parent_id}, orphan_node, _inserted_at} = entry ->
      case :ets.lookup(:causal_dag_session_registry, session_id) do
        [{^session_id, _}] ->
          table = :"dag_#{session_id}"
          attach_expired_orphan(session_id, table, orphan_node)
          :ets.delete_object(:causal_dag_orphan_buffer, entry)

        [] ->
          :ets.delete_object(:causal_dag_orphan_buffer, entry)
      end
    end)

    Process.send_after(self(), :check_orphans, 5_000)
    {:noreply, state}
  end

  def handle_info({:prune_session, session_id}, state) do
    table = :"dag_#{session_id}"

    try do
      :ets.delete(table)
    rescue
      ArgumentError -> :ok
    end

    :ets.delete(:causal_dag_session_registry, session_id)
    {:noreply, %{state | pending_deletions: Map.delete(state.pending_deletions, session_id)}}
  end

  ## Private Functions

  @required_fields [:trace_id, :agent_id, :intent, :confidence_score, :entropy_score, :action_status, :timestamp]

  defp validate_fields(%Node{} = node) do
    missing =
      Enum.any?(@required_fields, fn field ->
        Map.get(node, field) == nil
      end)

    if missing, do: {:error, :missing_fields}, else: :ok
  end

  defp ensure_session_table(session_id) do
    table_name = :"dag_#{session_id}"

    case :ets.lookup(:causal_dag_session_registry, session_id) do
      [] ->
        :ets.new(table_name, [:set, :public, :named_table])
        :ets.insert(:causal_dag_session_registry, {session_id, table_name})

        topology_builder = Observatory.Gateway.TopologyBuilder

        if Code.ensure_loaded?(topology_builder) &&
             function_exported?(topology_builder, :subscribe_to_session, 1) do
          apply(topology_builder, :subscribe_to_session, [session_id])
        end

        table_name

      [{^session_id, existing}] ->
        existing
    end
  end

  defp do_insert(session_id, table, %Node{parent_step_id: nil} = node, state) do
    :ets.insert(table, {node.trace_id, node})
    broadcast_delta(session_id, [node], [], [])
    check_and_promote_orphans(session_id, table, node.trace_id)
    {:reply, :ok, state}
  end

  defp do_insert(session_id, table, node, state) do
    case :ets.lookup(table, node.parent_step_id) do
      [{_parent_id, parent}] ->
        case detect_cycle(table, node.trace_id, node.parent_step_id) do
          :cycle ->
            {:reply, {:error, :cycle_detected}, state}

          :no_cycle ->
            :ets.insert(table, {node.trace_id, node})
            updated_parent = %{parent | children: parent.children ++ [node.trace_id]}
            :ets.insert(table, {parent.trace_id, updated_parent})

            broadcast_delta(
              session_id,
              [node],
              [updated_parent],
              [%{from: node.parent_step_id, to: node.trace_id}]
            )

            check_and_promote_orphans(session_id, table, node.trace_id)
            {:reply, :ok, state}
        end

      [] ->
        :ets.insert(
          :causal_dag_orphan_buffer,
          {{session_id, node.parent_step_id}, node, System.monotonic_time(:millisecond)}
        )

        {:reply, :ok, state}
    end
  end

  defp detect_cycle(_table, _incoming_trace_id, nil), do: :no_cycle

  defp detect_cycle(table, incoming_trace_id, current_parent_id) do
    do_detect_cycle(table, incoming_trace_id, current_parent_id, 0)
  end

  defp do_detect_cycle(_table, _incoming_trace_id, nil, _hops), do: :no_cycle
  defp do_detect_cycle(_table, _incoming_trace_id, _current, hops) when hops >= 100, do: :no_cycle

  defp do_detect_cycle(table, incoming_trace_id, current_parent_id, hops) do
    case :ets.lookup(table, current_parent_id) do
      [{_id, found_node}] ->
        if found_node.trace_id == incoming_trace_id do
          :cycle
        else
          do_detect_cycle(table, incoming_trace_id, found_node.parent_step_id, hops + 1)
        end

      [] ->
        :no_cycle
    end
  end

  defp check_and_promote_orphans(session_id, table, trace_id) do
    orphans = :ets.lookup(:causal_dag_orphan_buffer, {session_id, trace_id})

    Enum.each(orphans, fn {{^session_id, ^trace_id}, orphan_node, _inserted_at} = entry ->
      case detect_cycle(table, orphan_node.trace_id, trace_id) do
        :cycle ->
          :ets.delete_object(:causal_dag_orphan_buffer, entry)

        :no_cycle ->
          :ets.insert(table, {orphan_node.trace_id, orphan_node})

          case :ets.lookup(table, trace_id) do
            [{^trace_id, parent}] ->
              updated_parent = %{parent | children: parent.children ++ [orphan_node.trace_id]}
              :ets.insert(table, {trace_id, updated_parent})

              broadcast_delta(
                session_id,
                [orphan_node],
                [updated_parent],
                [%{from: trace_id, to: orphan_node.trace_id}]
              )

            [] ->
              :ok
          end

          :ets.delete_object(:causal_dag_orphan_buffer, entry)
          check_and_promote_orphans(session_id, table, orphan_node.trace_id)
      end
    end)

    :ok
  end

  defp attach_expired_orphan(session_id, table, orphan_node) do
    root = find_first_root(table)

    case root do
      nil ->
        orphan_with_flag = %{orphan_node | orphan: true, parent_step_id: nil}
        :ets.insert(table, {orphan_with_flag.trace_id, orphan_with_flag})
        broadcast_delta(session_id, [orphan_with_flag], [], [])

      {root_id, root_node} ->
        orphan_with_flag = %{orphan_node | orphan: true, parent_step_id: root_id}
        :ets.insert(table, {orphan_with_flag.trace_id, orphan_with_flag})
        updated_root = %{root_node | children: root_node.children ++ [orphan_with_flag.trace_id]}
        :ets.insert(table, {root_id, updated_root})

        broadcast_delta(
          session_id,
          [orphan_with_flag],
          [updated_root],
          [%{from: root_id, to: orphan_with_flag.trace_id}]
        )
    end
  end

  defp find_first_root(table) do
    table
    |> :ets.tab2list()
    |> Enum.find(fn {_trace_id, dag_node} -> dag_node.parent_step_id == nil end)
  end

  defp broadcast_delta(session_id, added_nodes, updated_nodes, added_edges) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "session:dag:#{session_id}",
      %{
        event: "dag_delta",
        session_id: session_id,
        added_nodes: added_nodes,
        updated_nodes: updated_nodes,
        added_edges: added_edges
      }
    )
  end
end
