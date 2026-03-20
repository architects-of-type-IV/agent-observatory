defmodule Ichor.Signals.ProtocolTracker do
  @moduledoc """
  Tracks messages across communication protocols (HTTP events, PubSub,
  Mailbox ETS, CommandQueue filesystem) and correlates them into
  end-to-end message traces.
  """
  use GenServer
  require Logger

  alias Ichor.Infrastructure.AgentProcess
  alias Ichor.Signals.Message

  @table_name :protocol_traces
  @max_traces 200

  # Client API

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Return all traces sorted by timestamp descending."
  @spec get_traces() :: [map()]
  def get_traces,
    do:
      :ets.tab2list(@table_name)
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

  @doc "Return aggregate protocol stats."
  @spec get_stats() :: map()
  def get_stats, do: GenServer.call(__MODULE__, :get_stats)

  @doc "Track a mailbox delivery for the given message."
  @spec track_mailbox_delivery(String.t(), String.t(), String.t()) :: :ok
  def track_mailbox_delivery(message_id, to, from) do
    GenServer.cast(__MODULE__, {:mailbox_delivery, message_id, to, from})
  end

  @doc "Track a command queue write for the given session."
  @spec track_command_write(String.t(), String.t()) :: :ok
  def track_command_write(session_id, command_id) do
    GenServer.cast(__MODULE__, {:command_write, session_id, command_id})
  end

  @doc "Track a gateway broadcast through the pipeline."
  @spec track_gateway_broadcast(map()) :: :ok
  def track_gateway_broadcast(data) do
    GenServer.cast(__MODULE__, {:gateway_broadcast, data})
  end

  # Server

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :public, :set])
    Ichor.Signals.subscribe(:events)
    Ichor.Signals.subscribe(:heartbeat)

    {:ok, %{trace_count: 0}}
  end

  @impl true
  def handle_info(%Message{name: :new_event, data: %{event: event}}, state) do
    state = maybe_create_trace(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message{name: :heartbeat}, state) do
    stats = compute_stats()

    Ichor.Signals.emit(:protocol_update, %{stats_map: stats})

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, compute_stats(), state}
  end

  @impl true
  def handle_cast({:mailbox_delivery, message_id, _to, _from}, state) do
    update_trace_hop(message_id, :mailbox, :delivered)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:command_write, _session_id, command_id}, state) do
    update_trace_hop(command_id, :command_queue, :pending)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:gateway_broadcast, data}, state) do
    to_label =
      case data.recipients do
        [single] -> single
        list when is_list(list) -> "#{length(list)} agents"
        _ -> data.channel
      end

    hops =
      [
        %{protocol: :gateway, status: :routed, at: data.timestamp, detail: data.channel}
      ] ++
        if data.delivered > 0 do
          [
            %{
              protocol: :mailbox,
              status: :delivered,
              at: DateTime.utc_now(),
              detail: "#{data.delivered} delivered"
            }
          ]
        else
          [
            %{
              protocol: :mailbox,
              status: :failed,
              at: DateTime.utc_now(),
              detail: "no recipients"
            }
          ]
        end

    trace = %{
      id: data.trace_id,
      type: :send_message,
      from: data.from || "unknown",
      to: to_label,
      content_preview: data.content_preview,
      message_type: "gateway",
      timestamp: data.timestamp,
      hops: hops
    }

    insert_trace(trace)
    {:noreply, %{state | trace_count: state.trace_count + 1}}
  end

  # Trace creation from events

  defp maybe_create_trace(
         %{hook_event_type: :PreToolUse, tool_name: "SendMessage"} = event,
         state
       ) do
    payload = event.payload || %{}

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
  end

  defp maybe_create_trace(%{hook_event_type: :PreToolUse, tool_name: "TeamCreate"} = event, state) do
    payload = event.payload || %{}

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
  end

  defp maybe_create_trace(%{hook_event_type: :SubagentStart} = event, state) do
    payload = event.payload || %{}

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
  end

  defp maybe_create_trace(_event, state), do: state

  defp insert_trace(trace) do
    :ets.insert(@table_name, {trace.id, trace})
    prune_traces()
  end

  defp update_trace_hop(trace_id, protocol, status) do
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
    size = :ets.info(@table_name, :size)

    if size > @max_traces do
      :ets.tab2list(@table_name)
      |> Enum.sort_by(fn {_, t} -> t.timestamp end, {:asc, DateTime})
      |> Stream.take(size - @max_traces)
      |> Enum.each(fn {id, _} -> :ets.delete(@table_name, id) end)
    end
  end

  # Stats

  defp compute_stats do
    traces = :ets.tab2list(@table_name) |> Enum.map(&elem(&1, 1))
    agent_processes = AgentProcess.list_all()

    %{
      traces: :ets.info(@table_name, :size),
      by_type: Enum.frequencies_by(traces, & &1.type),
      mailbox: %{
        agents: length(agent_processes),
        total_unread: 0
      }
    }
  end

  # Helpers

  defp truncate(nil, _len), do: ""

  defp truncate(str, len) when is_binary(str) and byte_size(str) > len,
    do: String.slice(str, 0, len) <> "..."

  defp truncate(str, _len) when is_binary(str), do: str
  defp truncate(_, _), do: ""

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
