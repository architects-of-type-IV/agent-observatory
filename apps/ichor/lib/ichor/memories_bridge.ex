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

  alias Ichor.Archon.MemoriesClient
  alias Ichor.Gateway.AgentRegistry.AgentEntry
  alias Ichor.Signals.{Catalog, Message}

  @flush_interval_ms :timer.seconds(30)

  # Signals that fire too frequently or carry no semantic value
  @ignored_signals [
    :heartbeat,
    :terminal_output,
    :protocol_update,
    :swarm_state,
    :dag_status,
    :topology_snapshot,
    :registry_changed
  ]

  # ── Public API ──────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec enabled?() :: boolean()
  def enabled? do
    case Application.get_env(:ichor, :memories) do
      nil -> false
      config -> Keyword.has_key?(config, :api_key)
    end
  end

  @spec stats() :: map()
  def stats, do: GenServer.call(__MODULE__, :stats)

  # ── GenServer Callbacks ────────────────────────────────────────────

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
    state = flush_buffers(state)
    schedule_flush()
    {:noreply, state}
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

  # ── Private ────────────────────────────────────────────────────────

  defp flush_buffers(state) do
    {sent, errors} =
      state.buffers
      |> Enum.filter(fn {_cat, signals} -> signals != [] end)
      |> Enum.reduce({0, 0}, fn {category, signals}, {sent, errors} ->
        case send_episode(category, Enum.reverse(signals)) do
          :ok -> {sent + 1, errors}
          :error -> {sent, errors + 1}
        end
      end)

    %{
      state
      | buffers: %{},
        episodes_sent: state.episodes_sent + sent,
        errors: state.errors + errors
    }
  end

  defp send_episode(category, signals) do
    content = build_episode_content(category, signals)
    space = "project:ichor:#{category}"

    case MemoriesClient.ingest(content,
           type: "text",
           source: "system",
           space: space
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

  # ── Signal Narration ───────────────────────────────────────────────
  # Produce natural language so the Memories extraction LLM can
  # identify entities (agents, teams, subsystems) and facts (relationships,
  # state changes, causal events) from the episode content.

  defp narrate(:agent_started, %{session_id: sid, role: role, team: team}),
    do: "Agent \"#{sid}\" started with role #{role} on team \"#{team}\"."

  defp narrate(:agent_stopped, %{session_id: sid, reason: reason}),
    do: "Agent \"#{sid}\" stopped. Reason: #{reason}."

  defp narrate(:agent_paused, %{session_id: sid}),
    do: "Agent \"#{sid}\" was paused by the human-in-the-loop relay."

  defp narrate(:agent_resumed, %{session_id: sid}),
    do: "Agent \"#{sid}\" was resumed."

  defp narrate(:agent_crashed, %{session_id: sid, team_name: team}),
    do: "Agent \"#{sid}\" on team \"#{team}\" crashed."

  defp narrate(:agent_spawned, %{session_id: sid, name: name, capability: cap}),
    do: "Agent \"#{name}\" (session #{sid}) was spawned with capability #{cap}."

  defp narrate(:team_created, %{name: name}),
    do: "Team \"#{name}\" was created."

  defp narrate(:team_disbanded, %{team_name: name}),
    do: "Team \"#{name}\" was disbanded."

  defp narrate(:nudge_warning, %{session_id: sid, agent_name: name, level: lvl}),
    do: "Agent \"#{name}\" (#{sid}) received a nudge escalation at level #{lvl}."

  defp narrate(:nudge_escalated, %{session_id: sid, agent_name: name}),
    do: "Agent \"#{name}\" (#{sid}) was paused due to nudge escalation."

  defp narrate(:nudge_zombie, %{session_id: sid, agent_name: name}),
    do: "Agent \"#{name}\" (#{sid}) was classified as a zombie process."

  defp narrate(:entropy_alert, %{session_id: sid, entropy_score: score}),
    do: "Entropy alert for agent \"#{sid}\": repeated pattern detected (score #{score})."

  defp narrate(:decision_log, %{log: log}),
    do: "Gateway routing decision: #{truncate(inspect(log), 200)}."

  defp narrate(:schema_violation, _data),
    do: "A schema validation violation was detected in the event pipeline."

  defp narrate(:dead_letter, %{delivery: d}),
    do: "A message was sent to the dead letter queue: #{truncate(inspect(d), 150)}."

  defp narrate(:message_delivered, %{agent_id: aid, msg_map: msg}),
    do: "Message delivered to agent \"#{aid}\": #{truncate(msg_content(msg), 200)}."

  defp narrate(:task_created, %{task: task}),
    do: "Task created: #{truncate(inspect(task), 200)}."

  defp narrate(:task_updated, %{task: task}),
    do: "Task status changed: #{truncate(inspect(task), 200)}."

  defp narrate(:agent_done, %{session_id: sid, summary: summary}),
    do: "Agent \"#{sid}\" completed its work. Summary: #{truncate(summary, 200)}."

  defp narrate(:agent_blocked, %{session_id: sid, reason: reason}),
    do: "Agent \"#{sid}\" is blocked. Reason: #{truncate(reason, 200)}."

  defp narrate(:mes_cycle_started, %{run_id: rid, team_name: team}),
    do: "MES manufacturing cycle #{rid} started with team \"#{team}\"."

  defp narrate(:mes_team_ready, %{session: session, agent_count: n}),
    do: "MES team \"#{session}\" is ready with #{n} agents."

  defp narrate(:mes_cycle_timeout, %{run_id: rid, team_name: team}),
    do: "MES cycle #{rid} (team \"#{team}\") exceeded its time budget and was killed."

  defp narrate(:mes_project_created, %{title: title, run_id: rid}),
    do: "MES project brief \"#{title}\" was created from run #{rid}."

  defp narrate(:mes_project_picked_up, %{project_id: pid, session_id: sid}),
    do:
      "MES project #{AgentEntry.short_id(pid)} was claimed by agent \"#{sid}\" for implementation."

  defp narrate(:mes_subsystem_loaded, %{subsystem: sub, modules: mods}),
    do: "Subsystem #{sub} was hot-loaded into the BEAM VM (#{length(mods)} modules)."

  defp narrate(:mes_janitor_cleaned, %{run_id: rid, trigger: trigger}),
    do: "MES janitor cleaned up run #{rid} (trigger: #{trigger})."

  defp narrate(:mes_team_killed, %{session: session}),
    do: "MES team session \"#{session}\" was killed."

  defp narrate(:new_event, %{event: event}),
    do: "Hook event received: #{truncate(inspect(event), 200)}."

  defp narrate(:gate_passed, %{session_id: sid}),
    do: "Agent \"#{sid}\" passed a quality gate."

  defp narrate(:gate_failed, %{session_id: sid, output: output}),
    do: "Agent \"#{sid}\" failed a quality gate: #{truncate(output, 150)}."

  defp narrate(:block_changed, %{block_id: bid, label: label}),
    do: "Memory block \"#{label}\" (#{bid}) was modified."

  defp narrate(name, data) do
    fields =
      data
      |> Map.drop([:scope_id])
      |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{truncate(inspect(v), 60)}" end)

    "Signal #{name} occurred#{if fields != "", do: ": #{fields}", else: ""}."
  end

  defp msg_content(%{content: c}) when is_binary(c), do: c
  defp msg_content(msg), do: inspect(msg, limit: 5)

  defp truncate(str, max) when byte_size(str) > max, do: String.slice(str, 0, max - 3) <> "..."
  defp truncate(str, _max), do: str

  defp schedule_flush, do: Process.send_after(self(), :flush, @flush_interval_ms)
end
