defmodule Observatory.ProtocolTracker do
  @moduledoc """
  Tracks messages across communication protocols (HTTP events, PubSub,
  Mailbox ETS, CommandQueue filesystem) and correlates them into
  end-to-end message traces.
  """
  use GenServer
  require Logger

  @table_name :protocol_traces
  @max_traces 200
  @stats_interval 5_000

  # ═══════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def get_traces,
    do:
      :ets.tab2list(@table_name)
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

  def get_stats, do: GenServer.call(__MODULE__, :get_stats)

  # Called by Mailbox when a message is delivered to ETS
  def track_mailbox_delivery(message_id, to, from) do
    GenServer.cast(__MODULE__, {:mailbox_delivery, message_id, to, from})
  end

  # Called by CommandQueue when a command file is written
  def track_command_write(session_id, command_id) do
    GenServer.cast(__MODULE__, {:command_write, session_id, command_id})
  end

  # ═══════════════════════════════════════════════════════
  # Server
  # ═══════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :public, :set])
    Phoenix.PubSub.subscribe(Observatory.PubSub, "events:stream")
    Process.send_after(self(), :broadcast_stats, @stats_interval)

    {:ok, %{trace_count: 0}}
  end

  @impl true
  def handle_info({:new_event, event}, state) do
    state = maybe_create_trace(event, state)
    {:noreply, state}
  end

  def handle_info(:broadcast_stats, state) do
    Process.send_after(self(), :broadcast_stats, @stats_interval)
    stats = compute_stats()

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "protocols:update",
      {:protocol_update, stats}
    )

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, compute_stats(), state}
  end

  @impl true
  def handle_cast({:mailbox_delivery, message_id, to, _from}, state) do
    update_trace_hop(message_id, :mailbox, :delivered, to)
    {:noreply, state}
  end

  def handle_cast({:command_write, session_id, command_id}, state) do
    update_trace_hop(command_id, :command_queue, :pending, session_id)
    {:noreply, state}
  end

  # ═══════════════════════════════════════════════════════
  # Trace creation from events
  # ═══════════════════════════════════════════════════════

  defp maybe_create_trace(event, state) do
    payload = event.payload || %{}

    cond do
      # SendMessage events create message traces
      event.hook_event_type == :PreToolUse && event.tool_name == "SendMessage" ->
        trace = %{
          id: event.tool_use_id || generate_id(),
          type: :send_message,
          from: event.session_id,
          to:
            get_in(payload, ["tool_input", "recipient"]) ||
              get_in(payload, ["tool_input", "target_agent_id"]) || "unknown",
          content_preview: get_in(payload, ["tool_input", "content"]) |> truncate(100),
          message_type: get_in(payload, ["tool_input", "type"]) || "message",
          timestamp: event.inserted_at,
          hops: [
            %{
              protocol: :http,
              status: :received,
              at: event.inserted_at,
              detail: "PreToolUse/SendMessage"
            }
          ]
        }

        insert_trace(trace)
        %{state | trace_count: state.trace_count + 1}

      # TeamCreate events
      event.hook_event_type == :PreToolUse && event.tool_name == "TeamCreate" ->
        trace = %{
          id: event.tool_use_id || generate_id(),
          type: :team_create,
          from: event.session_id,
          to: "system",
          content_preview: get_in(payload, ["tool_input", "team_name"]) || "team",
          message_type: "team_create",
          timestamp: event.inserted_at,
          hops: [
            %{protocol: :http, status: :received, at: event.inserted_at, detail: "TeamCreate"}
          ]
        }

        insert_trace(trace)
        %{state | trace_count: state.trace_count + 1}

      # Task tool spawns
      event.hook_event_type == :SubagentStart ->
        trace = %{
          id: event.tool_use_id || generate_id(),
          type: :agent_spawn,
          from: event.session_id,
          to: get_in(payload, ["subagent_id"]) || "subagent",
          content_preview: get_in(payload, ["description"]) || "spawn",
          message_type: "subagent_start",
          timestamp: event.inserted_at,
          hops: [
            %{protocol: :http, status: :received, at: event.inserted_at, detail: "SubagentStart"}
          ]
        }

        insert_trace(trace)
        %{state | trace_count: state.trace_count + 1}

      true ->
        state
    end
  end

  defp insert_trace(trace) do
    :ets.insert(@table_name, {trace.id, trace})
    prune_traces()
  end

  defp update_trace_hop(trace_id, protocol, status, _context) do
    case :ets.lookup(@table_name, trace_id) do
      [{^trace_id, trace}] ->
        hop = %{protocol: protocol, status: status, at: DateTime.utc_now(), detail: ""}
        updated = %{trace | hops: trace.hops ++ [hop]}
        :ets.insert(@table_name, {trace_id, updated})

      [] ->
        :ok
    end
  end

  defp prune_traces do
    all = :ets.tab2list(@table_name)

    if length(all) > @max_traces do
      all
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(& &1.timestamp, {:asc, DateTime})
      |> Enum.take(length(all) - @max_traces)
      |> Enum.each(fn trace -> :ets.delete(@table_name, trace.id) end)
    end
  end

  # ═══════════════════════════════════════════════════════
  # Stats
  # ═══════════════════════════════════════════════════════

  defp compute_stats do
    traces = :ets.tab2list(@table_name) |> Enum.map(&elem(&1, 1))
    mailbox_stats = Observatory.Mailbox.get_stats()
    queue_stats = Observatory.CommandQueue.get_queue_stats()

    %{
      traces: length(traces),
      by_type: Enum.frequencies_by(traces, & &1.type),
      mailbox: %{
        agents: length(mailbox_stats),
        total_pending: Enum.reduce(mailbox_stats, 0, fn s, acc -> acc + s.unread end)
      },
      command_queue: %{
        sessions: length(queue_stats),
        total_pending: Enum.reduce(queue_stats, 0, fn s, acc -> acc + s.pending_count end)
      },
      mailbox_detail: mailbox_stats,
      queue_detail: queue_stats
    }
  end

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp truncate(nil, _len), do: ""

  defp truncate(str, len) when is_binary(str) and byte_size(str) > len,
    do: String.slice(str, 0, len) <> "..."

  defp truncate(str, _len) when is_binary(str), do: str
  defp truncate(_, _), do: ""

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
