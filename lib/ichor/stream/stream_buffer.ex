defmodule Ichor.Stream.StreamBuffer do
  @moduledoc """
  Subscribes to all static PubSub topics and captures events into a ring buffer.
  Re-broadcasts each captured event on "stream:feed" for the /stream LiveView page.
  """
  use GenServer

  @max_events 500
  @table :stream_buffer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Return the last N captured events, newest first."
  @spec recent(non_neg_integer()) :: [map()]
  def recent(limit \\ 100) do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {_id, e} -> e.seq end, :desc)
    |> Enum.take(limit)
    |> Enum.map(&elem(&1, 1))
  rescue
    ArgumentError -> []
  end

  # ── Server ──────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])

    topics = Ichor.Stream.TopicCatalog.subscribable_topics()
    Enum.each(topics, &Phoenix.PubSub.subscribe(Ichor.PubSub, &1))

    {:ok, %{seq: 0}}
  end

  @impl true
  def handle_info(msg, %{seq: seq} = state) do
    next = seq + 1
    {topic, shape, summary} = classify(msg)

    entry = %{
      seq: next,
      topic: topic,
      shape: shape,
      summary: summary,
      at: DateTime.utc_now(),
      raw: sanitize_raw(msg)
    }

    :ets.insert(@table, {next, entry})
    maybe_evict(next)

    Phoenix.PubSub.broadcast(Ichor.PubSub, "stream:feed", {:stream_event, entry})

    {:noreply, %{state | seq: next}}
  end

  # ── Classification ──────────────────────────────────────────────────
  # Maps raw PubSub messages to {topic, shape_label, human_summary}.

  defp classify({:new_event, event}) do
    tool = event.tool_name || ""
    type = event.hook_event_type
    sid = short(event.session_id)
    {"events:stream", ":new_event", "#{type} #{tool} [#{sid}]"}
  end

  defp classify({:heartbeat, count}) do
    {"heartbeat", ":heartbeat", "beat ##{count}"}
  end

  defp classify({:decision_log, msg}) do
    from = msg_field(msg, :from) || msg_field(msg, "from") || "?"
    to = msg_field(msg, :to) || msg_field(msg, "to") || "?"
    {"gateway:messages", ":decision_log", "#{short(from)} -> #{short(to)}"}
  end

  defp classify({:agent_crashed, sid, team, count}) do
    {"agent:crashes", ":agent_crashed", "#{short(sid)} team=#{team || "none"} reassigned=#{count}"}
  end

  defp classify({:nudge_warning, sid, name, level}) do
    {"agent:nudge", ":nudge_warning", "#{name || short(sid)} level=#{level}"}
  end

  defp classify({:nudge_sent, sid, name, level}) do
    {"agent:nudge", ":nudge_sent", "#{name || short(sid)} level=#{level}"}
  end

  defp classify({:nudge_escalated, sid, name, level}) do
    {"agent:nudge", ":nudge_escalated", "#{name || short(sid)} level=#{level}"}
  end

  defp classify({:nudge_zombie, sid, name, level}) do
    {"agent:nudge", ":nudge_zombie", "#{name || short(sid)} level=#{level}"}
  end

  defp classify({:agent_started, id, meta}) do
    role = meta[:role] || "?"
    team = meta[:team] || "standalone"
    {"fleet:lifecycle", ":agent_started", "#{short(id)} role=#{role} team=#{team}"}
  end

  defp classify({:agent_stopped, id, reason}) do
    {"fleet:lifecycle", ":agent_stopped", "#{short(id)} reason=#{inspect(reason)}"}
  end

  defp classify({:agent_paused, id}), do: {"fleet:lifecycle", ":agent_paused", short(id)}
  defp classify({:agent_resumed, id}), do: {"fleet:lifecycle", ":agent_resumed", short(id)}
  defp classify({:team_created, name, _meta}), do: {"fleet:lifecycle", ":team_created", name}
  defp classify({:team_disbanded, name}), do: {"fleet:lifecycle", ":team_disbanded", name}
  defp classify(:hosts_changed), do: {"fleet:lifecycle", ":hosts_changed", "cluster membership changed"}

  defp classify(:registry_changed), do: {"gateway:registry", ":registry_changed", ""}

  defp classify({:schema_violation, _ev}), do: {"gateway:violations", ":schema_violation", ""}

  defp classify({:capability_update, _state}), do: {"gateway:capabilities", ":capability_update", ""}

  defp classify({:dead_letter, _delivery}), do: {"gateway:dlq", ":dead_letter", "webhook delivery failed"}

  defp classify({:gateway_audit, audit}) do
    channel = audit[:channel] || "?"
    {"gateway:audit", ":gateway_audit", "channel=#{channel}"}
  end

  defp classify({:protocol_update, _stats}), do: {"protocols:update", ":protocol_update", "stats recomputed"}

  defp classify({:gate_passed, sid, task_id, _done}) do
    {"quality:gate", ":gate_passed", "#{short(sid)} task=#{task_id}"}
  end

  defp classify({:gate_failed, sid, task_id, _done, _output}) do
    {"quality:gate", ":gate_failed", "#{short(sid)} task=#{task_id}"}
  end

  defp classify({:agent_done, sid, _aid, summary}) do
    {"pane:signals", ":agent_done", "#{short(sid)} #{String.slice(summary || "", 0, 60)}"}
  end

  defp classify({:agent_blocked, sid, _aid, reason}) do
    {"pane:signals", ":agent_blocked", "#{short(sid)} #{String.slice(reason || "", 0, 60)}"}
  end

  defp classify({:swarm_state, _state}), do: {"swarm:update", ":swarm_state", "pipeline state recomputed"}

  defp classify({:message_delivered, aid, _msg}) do
    {"messages:stream", ":message_delivered", "to #{short(aid)}"}
  end

  defp classify({:tasks_updated, team}), do: {"teams:update", ":tasks_updated", team}

  defp classify({:block_changed, _block_id, label}), do: {"memory:blocks", ":block_changed", label || ""}

  defp classify({:mesh_pause, _meta}), do: {"gateway:mesh_control", ":mesh_pause", "god mode"}

  defp classify({:dashboard_command, cmd}), do: {"dashboard:commands", ":dashboard_command", inspect(cmd)}

  # Catch-all for unclassified messages
  defp classify(msg) do
    {"unknown", inspect(elem(msg, 0)), String.slice(inspect(msg), 0, 120)}
  rescue
    _ -> {"unknown", "?", String.slice(inspect(msg), 0, 120)}
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp short(nil), do: "?"
  defp short(id) when is_binary(id) and byte_size(id) > 12, do: String.slice(id, 0, 8)
  defp short(id) when is_binary(id), do: id
  defp short(id), do: inspect(id)

  defp msg_field(msg, key) when is_struct(msg), do: Map.get(msg, key)
  defp msg_field(msg, key) when is_map(msg), do: Map.get(msg, key)
  defp msg_field(_, _), do: nil

  defp sanitize_raw(msg) do
    msg
    |> inspect(limit: 300, printable_limit: 300)
    |> String.slice(0, 500)
  end

  defp maybe_evict(current_seq) when current_seq > @max_events do
    cutoff = current_seq - @max_events

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {id, _} -> id <= cutoff end)
    |> Enum.each(fn {id, _} -> :ets.delete(@table, id) end)
  end

  defp maybe_evict(_), do: :ok
end
