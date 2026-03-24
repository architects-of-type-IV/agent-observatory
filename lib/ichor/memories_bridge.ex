defmodule Ichor.MemoriesBridge do
  @moduledoc """
  Bridges the Ichor signal stream into the Memories knowledge graph.

  Subscribes to all signal categories. Batches signals into time-windowed
  episodes and sends them to the Memories API for digestion. Memories
  handles entity extraction, fact extraction, and graph sync in its own
  Oban queues.

  Batching strategy:
  - Signals accumulate in a buffer per category
  - Every @flush_interval_ms, non-empty buffers are flushed as episodes
  - Each episode = one category's signals over that window
  - Noisy signals (heartbeat, terminal_output) are filtered out

  Space namespacing: all episodes go into "project:ichor:{category}"
  so Memories builds a per-domain knowledge graph.
  """

  use GenServer

  require Logger

  alias Ichor.Infrastructure.MemoriesClient
  alias Ichor.Signals.{Catalog, Message}
  alias Ichor.Workshop.AgentEntry

  @flush_interval_ms :timer.seconds(30)

  # Signals that fire too frequently or carry no semantic value
  @ignored_signals [
    :heartbeat,
    :terminal_output,
    :protocol_update,
    :pipeline_status,
    :topology_snapshot,
    :registry_changed
  ]

  @uuid_re ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-/i

  @extraction_instructions """
  This is ICHOR IV agent control plane telemetry. \
  Agent names like "lead", "worker-1", "researcher" are roles, not people. \
  Session IDs (mes-XXXXX) are ephemeral runtime identifiers. \
  Elixir modules (Ichor.Mesh.*) are code components, not documents. \
  Signal names (dag_delta, fleet_changed) are event types, not entities. \
  Focus on: which agents performed what actions, decisions made and their outcomes, \
  causal relationships between agent actions, team structure and coordination patterns.\
  """

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Returns true if the Memories API key is configured."
  @spec enabled?() :: boolean()
  def enabled? do
    case Application.get_env(:ichor, :memories) do
      nil -> false
      config -> Keyword.has_key?(config, :api_key)
    end
  end

  @doc "Return bridge stats: buffer sizes, episodes sent, signals processed, and error count."
  @spec stats() :: map()
  def stats, do: GenServer.call(__MODULE__, :stats)

  @impl true
  def init(_opts) do
    if enabled?() do
      Enum.each(Catalog.categories(), &Ichor.Signals.subscribe/1)
      schedule_flush()

      Logger.info("[MemoriesBridge] Started. Bridging signals to Memories knowledge graph.")

      {:ok,
       %{
         buffers: %{},
         episodes_sent: 0,
         signals_processed: 0,
         errors: 0
       }}
    else
      Logger.info("[MemoriesBridge] Disabled (no Memories API key configured).")
      :ignore
    end
  end

  @impl true
  def handle_info(%Message{name: name} = sig, state)
      when name not in @ignored_signals do
    category = sig.domain
    buffers = Map.update(state.buffers, category, [sig], &[sig | &1])

    {:noreply, %{state | buffers: buffers, signals_processed: state.signals_processed + 1}}
  end

  def handle_info(%Message{}, state), do: {:noreply, state}

  def handle_info(:flush, state) do
    me = self()
    buffers = state.buffers

    if Enum.any?(buffers, fn {_cat, signals} -> signals != [] end) do
      Task.Supervisor.start_child(Ichor.TaskSupervisor, fn ->
        {sent, errors} = do_flush(buffers)
        send(me, {:flush_result, sent, errors})
      end)
    end

    schedule_flush()
    {:noreply, %{state | buffers: %{}}}
  end

  def handle_info({:flush_result, sent, errors}, state) do
    {:noreply,
     %{state | episodes_sent: state.episodes_sent + sent, errors: state.errors + errors}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       buffer_sizes: Map.new(state.buffers, fn {k, v} -> {k, length(v)} end),
       episodes_sent: state.episodes_sent,
       signals_processed: state.signals_processed,
       errors: state.errors
     }, state}
  end

  defp do_flush(buffers) do
    buffers
    |> Enum.filter(fn {_cat, signals} -> signals != [] end)
    |> Enum.reduce({0, 0}, fn {category, signals}, {sent, errors} ->
      content = build_episode_content(category, Enum.reverse(signals))

      if worth_ingesting?(content) do
        case send_episode(category, content) do
          :ok -> {sent + 1, errors}
          :error -> {sent, errors + 1}
        end
      else
        {sent, errors}
      end
    end)
  end

  defp worth_ingesting?(content) do
    body =
      content
      |> String.split("\n", parts: 3)
      |> List.last("")

    unique_lines =
      body
      |> String.split("\n", trim: true)
      |> Enum.uniq()

    String.length(Enum.join(unique_lines)) >= 80
  end

  defp send_episode(category, content) do
    space = "project:ichor:#{category}"

    case MemoriesClient.ingest(content,
           type: "text",
           source: "system",
           space: space,
           extraction_instructions: @extraction_instructions
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[MemoriesBridge] Failed to ingest #{category} episode: #{inspect(reason)}"
        )

        :error
    end
  end

  defp build_episode_content(category, signals) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    body =
      signals
      |> Enum.map(fn sig -> narrate(sig.name, sig.data) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    "ICHOR IV control plane observations (#{category} domain, #{timestamp}):\n\n#{body}"
  end

  # -- Agent lifecycle --------------------------------------------------------

  defp narrate(:agent_started, %{name: name, role: role, team: team}),
    do: "Agent \"#{name}\" started with role #{role} on team \"#{team}\"."

  defp narrate(:agent_stopped, %{name: name, reason: reason}),
    do: "Agent \"#{name}\" stopped. Reason: #{reason}."

  defp narrate(:agent_paused, %{name: name}),
    do: "Agent \"#{name}\" was paused by the human-in-the-loop relay."

  defp narrate(:agent_resumed, %{name: name}),
    do: "Agent \"#{name}\" was resumed."

  defp narrate(:agent_crashed, %{session_id: sid, team_name: team}),
    do: "Agent \"#{sid}\" on team \"#{team}\" crashed."

  defp narrate(:agent_spawned, %{session_id: sid, name: name, capability: cap}),
    do: "Agent \"#{name}\" (session #{sid}) was spawned with capability #{cap}."

  defp narrate(:agent_done, %{session_id: sid, summary: summary}),
    do: "Agent \"#{sid}\" completed its work. Summary: #{truncate(summary, 200)}."

  defp narrate(:agent_blocked, %{session_id: sid, reason: reason}),
    do: "Agent \"#{sid}\" is blocked. Reason: #{truncate(reason, 200)}."

  # -- Team lifecycle ---------------------------------------------------------

  defp narrate(:team_created, %{name: name}),
    do: "Team \"#{name}\" was created."

  defp narrate(:team_disbanded, %{team_name: name}),
    do: "Team \"#{name}\" was disbanded."

  defp narrate(:team_spawn_requested, %{team_name: name, source: source}),
    do: "Team \"#{name}\" spawn was requested (source: #{source})."

  defp narrate(:team_spawn_started, %{team_name: name}),
    do: "Team \"#{name}\" spawn process started."

  defp narrate(:team_spawn_ready, %{team_name: name, agent_count: n, session: session}),
    do: "Team \"#{name}\" is ready with #{n} agents (session: #{session})."

  defp narrate(:team_spawn_failed, %{team_name: name, reason: reason}),
    do: "Team \"#{name}\" spawn failed: #{truncate(to_string(reason), 150)}."

  # -- Session lifecycle ------------------------------------------------------

  defp narrate(:session_started, %{session_id: sid, model: model, cwd: cwd}),
    do: "Session \"#{sid}\" started (model: #{model || "unknown"}, cwd: #{cwd || "unknown"})."

  defp narrate(:session_ended, %{session_id: sid}),
    do: "Session \"#{sid}\" ended."

  # -- Watchdog / entropy -----------------------------------------------------

  defp narrate(:nudge_warning, %{session_id: sid, agent_name: name, level: lvl}),
    do: "Agent \"#{name}\" (#{sid}) received a nudge escalation at level #{lvl}."

  defp narrate(:nudge_escalated, %{session_id: sid, agent_name: name}),
    do: "Agent \"#{name}\" (#{sid}) was paused due to nudge escalation."

  defp narrate(:nudge_zombie, %{session_id: sid, agent_name: name}),
    do: "Agent \"#{name}\" (#{sid}) was classified as a zombie process."

  defp narrate(:entropy_alert, %{session_id: sid, entropy_score: score}),
    do: "Entropy alert for agent \"#{sid}\": repeated pattern detected (score #{score})."

  # -- Gateway / mesh ---------------------------------------------------------

  defp narrate(:decision_log, %{log: log}) do
    cognition = log.cognition || %{}
    action = log.action || %{}
    identity = log.identity || %{}

    agent = identity["agent_id"] || "unknown"
    intent = cognition["intent"] || "unknown"
    confidence = cognition["confidence_score"]
    tool = action["tool_call"] || action["tool_name"]
    status = action["action_status"] || "unknown"

    parts = ["Agent \"#{agent}\" decided to #{intent}"]
    parts = if tool, do: parts ++ ["via #{tool}"], else: parts
    parts = if confidence, do: parts ++ ["(confidence: #{confidence})"], else: parts
    parts = parts ++ ["-- status: #{status}"]

    Enum.join(parts, " ") <> "."
  end

  defp narrate(:dead_letter, %{delivery: d}) do
    to = d[:to] || d["to"] || "unknown"
    from = d[:from] || d["from"] || "unknown"
    "Dead letter: message from \"#{from}\" to \"#{to}\" could not be delivered."
  end

  defp narrate(:schema_violation, _data),
    do: "A schema validation violation was detected in the event pipeline."

  defp narrate(:agent_message_intercepted, data) do
    from = data[:from] || data[:agent_id] || "unknown"
    to = data[:to] || "unknown"
    content = data[:content] || ""
    "Agent \"#{from}\" sent message to \"#{to}\": #{truncate(content, 200)}."
  end

  # -- Causal DAG -------------------------------------------------------------

  defp narrate(:dag_delta, %{session_id: sid, added_nodes: nodes}) when is_list(nodes) do
    node_descriptions =
      for node <- Enum.take(nodes, 5) do
        intent = node.intent || "unknown"
        status = node.action_status || "pending"
        conf = node.confidence_score
        ent = node.entropy_score
        agent = node.agent_id || "unknown"

        scores =
          [if(conf, do: "confidence=#{conf}"), if(ent, do: "entropy=#{ent}")]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        "  - #{agent}: #{intent} (#{status}#{if scores != "", do: ", #{scores}", else: ""})"
      end

    overflow = if length(nodes) > 5, do: "\n  (#{length(nodes) - 5} more)", else: ""

    "Causal chain update for session \"#{sid}\" (#{length(nodes)} new steps):\n" <>
      Enum.join(node_descriptions, "\n") <> overflow
  end

  # -- Tasks ------------------------------------------------------------------

  defp narrate(:task_created, %{task: task}), do: narrate_task("created", task)
  defp narrate(:task_updated, %{task: task}), do: narrate_task("updated", task)

  # -- Monitoring / quality gates ---------------------------------------------

  defp narrate(:gate_passed, %{session_id: sid}),
    do: "Agent \"#{sid}\" passed a quality gate."

  defp narrate(:gate_failed, %{session_id: sid, output: output}),
    do: "Agent \"#{sid}\" failed a quality gate: #{truncate(output, 150)}."

  defp narrate(:watchdog_sweep, %{checked: checked, paused: paused}),
    do: "Watchdog sweep: checked #{checked} agents, paused #{paused}."

  # -- MES (manufacturing) ----------------------------------------------------

  defp narrate(:mes_cycle_started, %{run_id: rid, team_name: team}),
    do: "MES manufacturing cycle #{rid} started with team \"#{team}\"."

  defp narrate(:mes_team_ready, %{session: session, agent_count: n}),
    do: "MES team \"#{session}\" is ready with #{n} agents."

  defp narrate(:mes_cycle_timeout, %{run_id: rid, team_name: team}),
    do: "MES cycle #{rid} (team \"#{team}\") exceeded its time budget and was killed."

  defp narrate(:mes_project_created, %{title: title, run_id: rid}),
    do: "MES brief artifact \"#{title}\" was created from run #{rid}."

  defp narrate(:mes_project_picked_up, %{project_id: pid, session_id: sid}),
    do:
      "MES project #{AgentEntry.short_id(pid)} was claimed by agent \"#{sid}\" for implementation."

  defp narrate(:mes_plugin_loaded, %{plugin: plugin, modules: mods}),
    do: "Plugin #{plugin} was hot-loaded into the BEAM VM (#{length(mods)} modules)."

  defp narrate(:mes_maintenance_cleaned, %{run_id: rid, trigger: trigger}),
    do: "MES maintenance cleaned up run #{rid} (trigger: #{trigger})."

  defp narrate(:mes_team_killed, %{session: session}),
    do: "MES team session \"#{session}\" was killed."

  defp narrate(:mes_cycle_skipped, %{reason: reason}),
    do: "MES cycle skipped: #{reason}."

  defp narrate(:mes_cycle_failed, %{run_id: rid, reason: reason}),
    do: "MES cycle #{rid} failed: #{truncate(to_string(reason), 150)}."

  # -- Run lifecycle ----------------------------------------------------------

  defp narrate(:run_complete, %{kind: kind, run_id: rid, session: session}),
    do: "Run #{rid} (#{kind}) completed in session \"#{session}\"."

  defp narrate(:run_terminated, %{kind: kind, run_id: rid, session: session}),
    do: "Run #{rid} (#{kind}) was terminated in session \"#{session}\"."

  # -- Fleet changes ----------------------------------------------------------

  defp narrate(:fleet_changed, data) do
    agent = data[:agent_id]
    if agent, do: "Fleet topology changed (agent: #{agent}).", else: "Fleet topology changed."
  end

  # -- Hook events (raw) ------------------------------------------------------

  defp narrate(:new_event, %{event: event}) when is_map(event) do
    hook = event[:hook_event_type] || event["hook_event_type"] || "unknown"
    tool = event[:tool_name] || event["tool_name"]
    session = event[:session_id] || event["session_id"]

    base = "Hook event: #{hook}"
    base = if tool, do: base <> " (tool: #{tool})", else: base
    base = if session, do: base <> " for session #{session}", else: base
    base <> "."
  end

  # -- Memory blocks ----------------------------------------------------------

  defp narrate(:block_changed, %{block_id: bid, label: label}),
    do: "Memory block \"#{label}\" (#{bid}) was modified."

  defp narrate(:memory_changed, %{block_id: bid}),
    do: "Memory block #{bid} content changed."

  # -- Messages ---------------------------------------------------------------

  defp narrate(:message_delivered, %{agent_id: aid, msg_map: msg}),
    do: "Message delivered to agent \"#{aid}\": #{truncate(msg_content(msg), 200)}."

  # -- HITL -------------------------------------------------------------------

  defp narrate(:hitl_intervention_recorded, %{action: action, details: details}),
    do: "HITL intervention: #{action}. #{truncate(to_string(details), 150)}."

  defp narrate(:hitl_auto_released, %{session_id: sid}),
    do: "HITL auto-released agent \"#{sid}\"."

  # -- Catch-all: readable key=value without inspect() ------------------------

  defp narrate(name, data) when is_map(data) do
    fields =
      data
      |> Map.drop([:scope_id, :id, :os_pid, :trace_id, :run_id, :session_id])
      |> Enum.reject(fn {_k, v} -> uuid?(v) or is_struct(v) or is_map(v) or is_list(v) end)
      |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{truncate(to_string(v), 60)}" end)

    case fields do
      "" -> "#{name} occurred."
      _ -> "#{name}: #{fields}."
    end
  end

  defp narrate(name, _data), do: "#{name} occurred."

  defp narrate_task(verb, task) when is_map(task) do
    subject = task[:subject] || task["subject"] || "untitled"
    status = task[:status] || task["status"]
    owner = task[:owner] || task["owner"]
    priority = task[:priority] || task["priority"]

    parts = ["Task #{verb}: \"#{subject}\""]
    parts = if status, do: parts ++ ["status=#{status}"], else: parts
    parts = if owner && owner != "", do: parts ++ ["owner=#{owner}"], else: parts
    parts = if priority, do: parts ++ ["priority=#{priority}"], else: parts

    Enum.join(parts, ", ") <> "."
  end

  defp narrate_task(verb, task), do: "Task #{verb}: #{truncate(to_string(task), 200)}."

  defp uuid?(v) when is_binary(v), do: Regex.match?(@uuid_re, v)
  defp uuid?(_), do: false

  defp msg_content(%{content: c}) when is_binary(c), do: c
  defp msg_content(msg), do: inspect(msg, limit: 5)

  defp truncate(str, max) when byte_size(str) > max, do: String.slice(str, 0, max - 3) <> "..."
  defp truncate(str, _max), do: str

  defp schedule_flush, do: Process.send_after(self(), :flush, @flush_interval_ms)
end
