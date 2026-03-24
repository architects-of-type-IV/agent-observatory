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
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  catch
    :exit, {:noproc, _} -> %{}
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

  # Trace creation from events

  @trace_types %{
    {:PreToolUse, "SendMessage"} => :send_message,
    {:PreToolUse, "TeamCreate"} => :team_create,
    {:SubagentStart, nil} => :agent_spawn
  }

  defp maybe_create_trace(event, state) do
    key = {event.hook_event_type, event[:tool_name]}

    case Map.get(@trace_types, key) || Map.get(@trace_types, {event.hook_event_type, nil}) do
      nil ->
        state

      type ->
        trace = build_trace(type, event)
        insert_trace(trace)
        %{state | trace_count: state.trace_count + 1}
    end
  end

  defp build_trace(type, event) do
    payload = event.payload || %{}
    input = get_in(payload, ["tool_input"]) || payload

    {to, preview, detail} = trace_fields(type, input)

    %{
      id: event.tool_use_id || generate_id(),
      type: type,
      from: event.session_id,
      to: to,
      content_preview: String.slice(preview, 0, 100),
      message_type: to_string(type),
      timestamp: event.inserted_at,
      hops: [%{protocol: :http, status: :received, at: event.inserted_at, detail: detail}]
    }
  end

  defp trace_fields(:send_message, input) do
    to = input["recipient"] || input["target_agent_id"] || "unknown"
    {to, input["content"] || "", "PreToolUse/SendMessage"}
  end

  defp trace_fields(:team_create, input) do
    {"system", input["team_name"] || "team", "TeamCreate"}
  end

  defp trace_fields(:agent_spawn, input) do
    {input["subagent_id"] || "subagent", input["description"] || "spawn", "SubagentStart"}
  end

  defp insert_trace(trace) do
    :ets.insert(@table_name, {trace.id, trace})
    prune_traces()
  end

  defp prune_traces do
    size = :ets.info(@table_name, :size)

    if size > @max_traces do
      evict_count = size - @max_traces

      :ets.foldl(
        fn {id, t}, acc -> evict_candidate(acc, id, t.timestamp, evict_count) end,
        %{},
        @table_name
      )
      |> Map.keys()
      |> Enum.each(&:ets.delete(@table_name, &1))
    end
  end

  defp evict_candidate(acc, id, ts, evict_count) when map_size(acc) < evict_count do
    Map.put(acc, id, ts)
  end

  defp evict_candidate(acc, id, ts, _evict_count) do
    {newest_id, newest_ts} = Enum.max_by(acc, fn {_k, v} -> v end, DateTime)

    case DateTime.compare(ts, newest_ts) do
      :lt -> acc |> Map.delete(newest_id) |> Map.put(id, ts)
      _ -> acc
    end
  end

  # Stats

  defp compute_stats do
    traces = :ets.tab2list(@table_name) |> Enum.map(&elem(&1, 1))

    %{
      traces: :ets.info(@table_name, :size),
      by_type: Enum.frequencies_by(traces, & &1.type),
      mailbox: %{
        agents: length(AgentProcess.list_all()),
        total_unread: 0
      },
      command_queue: %{total_pending: 0}
    }
  end

  # Helpers

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
