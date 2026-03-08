defmodule Observatory.Gateway.AgentRegistry do
  @moduledoc """
  Unified fleet registry. Tracks all known agents, their status, team membership,
  and available delivery channels. Merges data from hook events, TeamWatcher,
  tmux sessions, and HeartbeatManager into a single queryable ETS table.
  """

  use GenServer
  require Logger

  @table :gateway_agent_registry
  @tmux_poll_interval 5_000
  @capture_poll_interval 1_500
  @ended_ttl_seconds 1_800
  @stale_ttl_seconds 3_600

  # ── Client API ───────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register or update an agent from a hook event."
  def register_from_event(event) do
    GenServer.cast(__MODULE__, {:register_event, event})
  end

  @doc "Update agent info from TeamWatcher data."
  def sync_teams(teams) do
    GenServer.cast(__MODULE__, {:sync_teams, teams})
  end

  @doc "Get a single agent by session_id."
  def get(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, agent}] -> agent
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "List all registered agents."
  def list_all do
    :ets.tab2list(@table) |> Enum.map(&elem(&1, 1))
  rescue
    ArgumentError -> []
  end

  @doc "Find agents matching a channel pattern."
  def resolve_channel(pattern) do
    case parse_channel(pattern) do
      {:agent, name} ->
        find_by_name_or_session(name)

      {:session, session_id} ->
        case get(session_id) do
          nil -> []
          agent -> [agent]
        end

      {:team, team_name} ->
        list_all()
        |> Enum.filter(fn a -> a.team == team_name end)

      {:role, role} ->
        role_atom = safe_to_atom(role)

        list_all()
        |> Enum.filter(fn a -> a.role == role_atom end)

      {:fleet, _} ->
        list_all() |> Enum.filter(fn a -> a.status == :active end)

      :unknown ->
        []
    end
  end

  @doc "Mark an agent as ended."
  def mark_ended(session_id) do
    GenServer.cast(__MODULE__, {:mark_ended, session_id})
  end

  @doc "Start watching an agent for terminal output (capture-pane polling)."
  def watch(session_id) do
    GenServer.cast(__MODULE__, {:watch, session_id})
  end

  @doc "Stop watching an agent for terminal output."
  def unwatch(session_id) do
    GenServer.cast(__MODULE__, {:unwatch, session_id})
  end

  @doc "Purge all stale/ended agents immediately. Returns count of purged entries."
  def purge_stale do
    GenServer.call(__MODULE__, :purge_stale)
  end

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])

    # Register the operator (dashboard UI) as a permanent agent for message delivery
    operator =
      default_agent("operator")
      |> Map.put(:id, "operator")
      |> Map.put(:role, :operator)
      |> Map.put(:status, :active)
      |> Map.put(:channels, %{tmux: nil, mailbox: "operator", webhook: nil})

    :ets.insert(@table, {"operator", operator})

    Phoenix.PubSub.subscribe(Observatory.PubSub, "teams:update")

    schedule_tmux_poll()
    {:ok, %{watched: MapSet.new(), last_capture: %{}}}
  end

  @impl true
  def handle_cast({:register_event, event}, state) do
    session_id = event.session_id
    existing = get(session_id) || default_agent(session_id)

    updated =
      existing
      |> maybe_update_from_event(event)
      |> Map.put(:last_event_at, DateTime.utc_now())
      |> Map.put(:status, derive_status(event, existing))

    # Identity merge: absorb team metadata from orphaned team-registered entries
    updated = maybe_absorb_team_entry(session_id, updated)

    :ets.insert(@table, {session_id, updated})
    broadcast_registry_update()
    {:noreply, state}
  end

  def handle_cast({:sync_teams, teams}, state) do
    # teams is a map or list from TeamWatcher
    teams_list =
      case teams do
        t when is_map(t) -> Map.values(t)
        t when is_list(t) -> t
        _ -> []
      end

    # Track which team names are currently alive
    live_team_names = Enum.map(teams_list, & &1.name) |> MapSet.new()

    # Sweep agents from teams that no longer exist
    :ets.tab2list(@table)
    |> Enum.each(fn {session_id, agent} ->
      if agent.team && not MapSet.member?(live_team_names, agent.team) do
        :ets.delete(@table, session_id)
      end
    end)

    # Pre-build cwd index for identity merge (avoids O(M*N) tab2list per member)
    unaffiliated_by_cwd =
      :ets.tab2list(@table)
      |> Enum.reduce(%{}, fn {key, agent}, acc ->
        if is_uuid?(key) && is_nil(agent.team) && agent.status == :active && agent.cwd do
          Map.update(acc, agent.cwd, [{key, agent}], &[{key, agent} | &1])
        else
          acc
        end
      end)

    for team <- teams_list, member <- team.members do
      member_key = member[:agent_id] || member[:session_id]

      if member_key do
        # Identity merge: find a UUID-keyed entry that matches this team member
        # by cwd correlation, rather than creating a duplicate short-name entry
        {canonical_key, existing} = find_canonical_entry(member_key, member, team.name, unaffiliated_by_cwd)

        # Build channel map: always set mailbox, wire tmux_pane_id when available
        tmux_target = resolve_tmux_target(member[:tmux_pane_id], existing.channels.tmux)

        updated_channels =
          existing.channels
          |> Map.put(:mailbox, canonical_key)
          |> Map.put(:tmux, tmux_target)

        qualified_id = qualify_agent_id(member[:name], team.name)
        is_active = member[:is_active] == true

        updated =
          existing
          |> Map.put(:id, qualified_id)
          |> Map.put(:short_name, member[:name] || existing.id)
          |> Map.put(:team, team.name)
          |> Map.put(:role, derive_role(member[:agent_type]))
          |> Map.put(:model, member[:model] || existing.model)
          |> Map.put(:cwd, member[:cwd] || existing.cwd)
          |> Map.put(:channels, updated_channels)
          |> Map.put(:status, if(is_active, do: :active, else: :ended))

        :ets.insert(@table, {canonical_key, updated})

        # Clean up the orphaned member_key entry if we merged into a different key
        if canonical_key != member_key do
          :ets.delete(@table, member_key)
        end
      end
    end

    broadcast_registry_update()
    {:noreply, state}
  end

  def handle_cast({:mark_ended, session_id}, state) do
    case get(session_id) do
      nil ->
        :ok

      agent ->
        :ets.insert(@table, {session_id, %{agent | status: :ended}})
        broadcast_registry_update()
    end

    {:noreply, state}
  end

  def handle_cast({:watch, session_id}, state) do
    new_watched = MapSet.put(state.watched, session_id)

    if MapSet.size(state.watched) == 0 do
      schedule_capture_poll()
    end

    {:noreply, %{state | watched: new_watched}}
  end

  def handle_cast({:unwatch, session_id}, state) do
    {:noreply, %{state | watched: MapSet.delete(state.watched, session_id)}}
  end

  @impl true
  def handle_call(:purge_stale, _from, state) do
    before = :ets.info(@table, :size)
    sweep_ended_agents()
    new_capture = sweep_stale_captures(state.watched, state.last_capture)
    after_count = :ets.info(@table, :size)
    broadcast_registry_update()
    {:reply, {:ok, before - after_count}, %{state | last_capture: new_capture}}
  end

  @impl true
  def handle_info({:teams_updated, teams}, state) do
    sync_teams(teams)
    {:noreply, state}
  end

  def handle_info(:poll_tmux, state) do
    poll_tmux_sessions()
    schedule_tmux_poll()
    {:noreply, state}
  end

  def handle_info(:poll_capture, state) do
    new_last = capture_watched_agents(state.watched, state.last_capture)

    if MapSet.size(state.watched) > 0 do
      schedule_capture_poll()
    end

    {:noreply, %{state | last_capture: new_last}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ─────────────────────────────────────────────────────────

  defp default_agent(session_id) do
    %{
      id: short_id(session_id),
      short_name: short_id(session_id),
      session_id: session_id,
      team: nil,
      role: :standalone,
      status: :active,
      model: nil,
      cwd: nil,
      current_tool: nil,
      started_at: DateTime.utc_now(),
      last_event_at: DateTime.utc_now(),
      channels: %{
        tmux: nil,
        mailbox: session_id,
        webhook: nil
      }
    }
  end

  defp qualify_agent_id(nil, _team_name), do: nil
  defp qualify_agent_id(name, team_name), do: "#{name}@#{team_name}"

  defp maybe_update_from_event(agent, event) do
    agent
    |> maybe_put(:model, event.model_name)
    |> maybe_put(:cwd, event.cwd)
    |> update_current_tool(event)
    |> update_session_start(event)
  end

  defp update_current_tool(agent, %{hook_event_type: type, tool_name: tool})
       when type in [:PreToolUse, "PreToolUse"] and not is_nil(tool) do
    %{agent | current_tool: tool}
  end

  defp update_current_tool(agent, %{hook_event_type: type})
       when type in [:PostToolUse, :PostToolUseFailure, "PostToolUse", "PostToolUseFailure"] do
    %{agent | current_tool: nil}
  end

  defp update_current_tool(agent, _event), do: agent

  defp update_session_start(agent, %{hook_event_type: type})
       when type in [:SessionStart, "SessionStart"] do
    %{agent | started_at: DateTime.utc_now()}
  end

  defp update_session_start(agent, _event), do: agent

  defp derive_status(%{hook_event_type: type}, _existing)
       when type in [:SessionEnd, "SessionEnd"],
       do: :ended

  defp derive_status(_event, existing), do: existing.status

  defp derive_role(nil), do: :standalone
  defp derive_role("team-lead"), do: :lead
  defp derive_role("lead"), do: :lead
  defp derive_role("coordinator"), do: :coordinator
  defp derive_role(_), do: :worker

  defp poll_tmux_sessions do
    tmux_sessions = Observatory.Gateway.Channels.Tmux.list_sessions()
    tmux_panes = Observatory.Gateway.Channels.Tmux.list_panes()
    all_entries = :ets.tab2list(@table)
    known_ids = all_entries |> Enum.map(fn {_sid, a} -> a.id end) |> MapSet.new()

    # Collect all tmux targets already wired to existing agents
    known_tmux_targets =
      all_entries
      |> Enum.flat_map(fn {_sid, a} ->
        case a.channels.tmux do
          nil -> []
          target -> [target]
        end
      end)
      |> MapSet.new()

    # Auto-register tmux sessions not yet in the registry
    # Skip sessions that are already wired as tmux targets on existing agents
    for session_name <- tmux_sessions,
        not MapSet.member?(known_ids, session_name),
        not MapSet.member?(known_tmux_targets, session_name),
        is_nil(get(session_name)) do
      agent =
        default_agent(session_name)
        |> Map.put(:id, session_name)
        |> Map.put(:channels, %{tmux: session_name, mailbox: session_name, webhook: nil})

      :ets.insert(@table, {session_name, agent})
    end

    # Enrich existing entries with tmux channel info
    # Match by: exact session name, pane ID from team config, or fuzzy name match
    # Reuse all_entries from above -- newly auto-registered sessions already have tmux set
    all_entries
    |> Enum.each(fn {session_id, agent} ->
      current_tmux = agent.channels.tmux

      # Skip if already has a valid tmux target
      unless current_tmux && tmux_target_alive?(current_tmux, tmux_sessions, tmux_panes) do
        matched_tmux = find_tmux_target(agent, tmux_sessions, tmux_panes)

        if matched_tmux && matched_tmux != current_tmux do
          updated_channels = Map.put(agent.channels, :tmux, matched_tmux)
          :ets.insert(@table, {session_id, %{agent | channels: updated_channels}})
        end
      end
    end)

    broadcast_registry_update()
  end

  defp find_tmux_target(agent, sessions, panes) do
    # 1. Exact session name match
    exact = Enum.find(sessions, &(&1 == agent.id))

    if exact do
      exact
    else
      # 2. Fuzzy session name match
      Enum.find(sessions, fn s ->
        String.starts_with?(s, agent.id) or String.contains?(s, agent.id)
      end)
      # 3. Check if any pane title contains agent name
      || Enum.find_value(panes, fn p ->
        if String.contains?(p.title || "", agent.id), do: p.pane_id
      end)
    end
  end

  defp tmux_target_alive?(target, sessions, panes) do
    target in sessions or Enum.any?(panes, &(&1.pane_id == target))
  end

  # Prefer tmux_pane_id from team config, fall back to existing channel value
  defp resolve_tmux_target(nil, existing), do: existing
  defp resolve_tmux_target("", existing), do: existing
  defp resolve_tmux_target(pane_id, _existing), do: pane_id

  # ── Identity Merge ──────────────────────────────────────────────────

  # Find the canonical ETS entry for a team member. Prefers UUID-keyed entries
  # (from hook events) over short-name-keyed entries (from TeamWatcher config).
  # Correlation: match by cwd among unaffiliated (team-less) active agents.
  defp find_canonical_entry(member_key, member, team_name, unaffiliated_by_cwd) do
    # First: check if we already have this member_key in ETS
    case get(member_key) do
      %{team: ^team_name} = existing ->
        # Already merged from a prior sync -- keep using this key
        {member_key, existing}

      _ ->
        # Try to find a UUID-keyed agent that correlates with this team member
        case correlate_by_cwd(member[:cwd], unaffiliated_by_cwd) do
          {uuid_key, uuid_agent} ->
            {uuid_key, uuid_agent}

          nil ->
            # No correlation found -- use the member_key (short name) as fallback
            existing = get(member_key) || default_agent(member_key)
            {member_key, existing}
        end
    end
  end

  # Look up a UUID-keyed agent with matching cwd from the pre-built index.
  # Returns {key, agent} or nil. Only matches if exactly one candidate exists
  # to avoid ambiguous merges (multiple agents in same cwd).
  defp correlate_by_cwd(nil, _index), do: nil

  defp correlate_by_cwd(cwd, index) do
    case Map.get(index, cwd, []) do
      [{key, agent}] -> {key, agent}
      # Zero or multiple matches -- ambiguous, skip merge
      _ -> nil
    end
  end

  # When a hook event registers a UUID-keyed agent, check if there's an orphaned
  # team-registered entry (short-name key) with matching cwd. If so, absorb its
  # team metadata and delete the orphan.
  defp maybe_absorb_team_entry(uuid_key, agent) do
    if is_uuid?(uuid_key) && is_nil(agent.team) && agent.cwd do
      # Use ets.match_object to filter server-side instead of copying the full table.
      # Match entries where cwd matches -- then filter non-UUID keys with a team in Elixir.
      orphan =
        :ets.match_object(@table, {:_, %{cwd: agent.cwd}})
        |> Enum.find(fn {key, a} ->
          not is_uuid?(key) &&
            a.team != nil &&
            key != "operator"
        end)

      case orphan do
        {orphan_key, orphan_agent} ->
          # Absorb team metadata from the orphan
          :ets.delete(@table, orphan_key)

          agent
          |> Map.put(:id, orphan_agent.id)
          |> Map.put(:short_name, orphan_agent.short_name)
          |> Map.put(:team, orphan_agent.team)
          |> Map.put(:role, orphan_agent.role)
          |> Map.merge(%{channels: merge_channels(agent.channels, orphan_agent.channels)})

        nil ->
          agent
      end
    else
      agent
    end
  rescue
    ArgumentError -> agent
  end

  defp merge_channels(hook_channels, team_channels) do
    %{
      tmux: team_channels.tmux || hook_channels.tmux,
      mailbox: hook_channels.mailbox || team_channels.mailbox,
      webhook: hook_channels.webhook || team_channels.webhook
    }
  end

  defp is_uuid?(str) when is_binary(str), do: match?({:ok, _}, Ecto.UUID.cast(str))
  defp is_uuid?(_), do: false

  defp schedule_tmux_poll do
    Process.send_after(self(), :poll_tmux, @tmux_poll_interval)
  end

  defp schedule_capture_poll do
    Process.send_after(self(), :poll_capture, @capture_poll_interval)
  end

  defp capture_watched_agents(watched, last_capture) do
    Enum.reduce(watched, last_capture, fn session_id, acc ->
      agent = get(session_id)
      tmux_target = agent && agent.channels.tmux

      if tmux_target do
        case Observatory.Gateway.Channels.Tmux.capture_pane(tmux_target) do
          {:ok, output} ->
            prev = Map.get(acc, session_id, "")

            if output != prev do
              # Broadcast the new terminal output
              Phoenix.PubSub.broadcast(
                Observatory.PubSub,
                "agent:#{session_id}:activity",
                {:terminal_output, session_id, output}
              )

              Map.put(acc, session_id, output)
            else
              acc
            end

          {:error, _} ->
            acc
        end
      else
        acc
      end
    end)
  end

  defp parse_channel("agent:" <> name), do: {:agent, name}
  defp parse_channel("session:" <> sid), do: {:session, sid}
  defp parse_channel("team:" <> name), do: {:team, name}
  defp parse_channel("role:" <> role), do: {:role, role}
  defp parse_channel("fleet:" <> rest), do: {:fleet, rest}
  defp parse_channel(_), do: :unknown

  defp find_by_name_or_session(name) do
    # Try exact ETS key match first
    case get(name) do
      nil ->
        # Search by qualified id, short_name, or session_id field
        # (session_id field may differ from ETS key after identity merge)
        list_all()
        |> Enum.filter(fn a ->
          a.id == name or
            Map.get(a, :short_name) == name or
            a.session_id == name
        end)

      agent ->
        [agent]
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp short_id(session_id) when is_binary(session_id) do
    String.slice(session_id, 0, 8)
  end

  defp safe_to_atom(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> String.to_atom(str)
    end
  end

  defp broadcast_registry_update do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "gateway:registry",
      :registry_changed
    )
  end

  defp sweep_ended_agents do
    now = DateTime.utc_now()
    ended_cutoff = DateTime.add(now, -@ended_ttl_seconds, :second)
    stale_cutoff = DateTime.add(now, -@stale_ttl_seconds, :second)

    # Get live team names from TeamWatcher
    live_teams =
      try do
        Observatory.TeamWatcher.get_state() |> Map.keys() |> MapSet.new()
      rescue
        _ -> nil
      end

    :ets.tab2list(@table)
    |> Enum.each(fn {session_id, agent} ->
      cond do
        # Never sweep the operator
        agent.id == "operator" ->
          :ok

        # Sweep agents from deleted teams
        agent.team && live_teams && not MapSet.member?(live_teams, agent.team) ->
          :ets.delete(@table, session_id)

        # Sweep ended agents after 30min
        agent.status == :ended &&
            DateTime.compare(agent.last_event_at, ended_cutoff) == :lt ->
          :ets.delete(@table, session_id)

        # Sweep standalone agents with no events in 1h (test probes, old sessions)
        agent.role == :standalone && is_nil(agent.team) &&
            DateTime.compare(agent.last_event_at, stale_cutoff) == :lt ->
          :ets.delete(@table, session_id)

        true ->
          :ok
      end
    end)
  rescue
    ArgumentError -> :ok
  end

  defp sweep_stale_captures(watched, last_capture) do
    Map.filter(last_capture, fn {sid, _} -> MapSet.member?(watched, sid) end)
  end
end
