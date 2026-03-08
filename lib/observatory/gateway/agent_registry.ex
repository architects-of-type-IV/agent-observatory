defmodule Observatory.Gateway.AgentRegistry do
  @moduledoc """
  Unified fleet registry. Tracks all known agents, their status, team membership,
  and available delivery channels. Merges data from hook events, TeamWatcher,
  tmux sessions, and HeartbeatManager into a single queryable ETS table.
  """

  use GenServer
  require Logger

  alias Observatory.Gateway.AgentRegistry.IdentityMerge

  @table :gateway_agent_registry
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

  @doc "List all raw ETS entries as `{session_id, agent}` tuples."
  def list_all_raw do
    :ets.tab2list(@table)
  rescue
    ArgumentError -> []
  end

  @doc "Register a tmux session discovered by TmuxDiscovery."
  def register_tmux_session(session_name) do
    agent =
      default_agent(session_name)
      |> Map.put(:id, session_name)
      |> Map.put(:channels, %{tmux: session_name, mailbox: session_name, webhook: nil})

    :ets.insert(@table, {session_name, agent})
  rescue
    ArgumentError -> :ok
  end

  @doc "Update the tmux channel for an existing agent."
  def update_tmux_channel(session_id, tmux_target) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, agent}] ->
        updated_channels = Map.put(agent.channels, :tmux, tmux_target)
        :ets.insert(@table, {session_id, %{agent | channels: updated_channels}})

      [] ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @doc "Broadcast a registry change notification."
  def broadcast_update do
    broadcast_registry_update()
  end

  @doc """
  Build a map keyed by all known identifiers (id, session_id, short_name) for each agent.
  When multiple entries collide on the same key, the active agent wins over ended.
  """
  def build_lookup(agents) do
    agents
    |> Enum.flat_map(fn a ->
      keys = [a.id, a.session_id, a.short_name] |> Enum.reject(&is_nil/1) |> Enum.uniq()
      Enum.map(keys, fn k -> {k, a} end)
    end)
    |> dedup_by_status()
  end

  @doc """
  Dedup a list of `{key, entry}` pairs: when multiple entries share a key,
  the one with `status: :active` wins.
  """
  def dedup_by_status(pairs) do
    Enum.reduce(pairs, %{}, fn {k, entry}, acc ->
      case Map.get(acc, k) do
        nil -> Map.put(acc, k, entry)
        %{status: :active} -> acc
        _existing -> Map.put(acc, k, entry)
      end
    end)
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

  @doc "Update last_event_at timestamp for an agent (activity signal from pane monitor)."
  def touch(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, agent}] ->
        :ets.insert(@table, {session_id, %{agent | last_event_at: DateTime.utc_now()}})

      [] ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end


  @doc """
  Register a spawned agent with optional parent tracking.
  Called by AgentSpawner after creating a tmux session.
  """
  def register_spawned(session_id, opts) do
    parent_id = opts[:parent_id]
    agent = default_agent(session_id)

    agent =
      agent
      |> Map.put(:id, opts[:name] || agent.id)
      |> Map.put(:short_name, opts[:name] || agent.short_name)
      |> Map.put(:role, opts[:role] || :worker)
      |> Map.put(:team, opts[:team])
      |> Map.put(:cwd, opts[:cwd])
      |> Map.put(:host, opts[:host] || "local")
      |> Map.put(:parent_id, parent_id)
      |> Map.put(:channels, Map.merge(agent.channels, opts[:channels] || %{}))

    :ets.insert(@table, {session_id, agent})

    broadcast_registry_update()
    agent
  rescue
    ArgumentError -> nil
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

    # Defer operator AgentProcess creation until FleetSupervisor is up
    Process.send_after(self(), :ensure_operator_process, 1_000)

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:register_event, %{session_id: session_id} = event}, state) do
    # Only register events from real Claude Code sessions (UUID session IDs)
    state = maybe_register_event(IdentityMerge.uuid?(session_id), session_id, event, state)
    {:noreply, state}
  end

  def handle_cast({:sync_teams, teams}, state) do
    teams_list = normalize_teams(teams)
    live_team_names = Enum.map(teams_list, & &1.name) |> MapSet.new()

    sweep_dead_teams(live_team_names)
    unaffiliated_by_cwd = build_cwd_index()

    for team <- teams_list, member <- team.members do
      sync_team_member(member, team.name, unaffiliated_by_cwd)
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

  @impl true
  def handle_call(:purge_stale, _from, state) do
    before = :ets.info(@table, :size)
    sweep_ended_agents()
    after_count = :ets.info(@table, :size)
    broadcast_registry_update()
    {:reply, {:ok, before - after_count}, state}
  end

  @impl true
  def handle_info({:teams_updated, teams}, state) do
    sync_teams(teams)
    {:noreply, state}
  end

  def handle_info(:ensure_operator_process, state) do
    ensure_agent_process("operator", role: :operator)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ─────────────────────────────────────────────────────────

  defp default_agent(session_id) do
    %{
      id: short_id(session_id),
      short_name: short_id(session_id),
      session_id: session_id,
      host: "local",
      parent_id: nil,
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
        ssh_tmux: nil,
        mailbox: session_id,
        webhook: nil
      }
    }
  end

  defp maybe_register_event(true, session_id, event, state) do
    existing = get(session_id) || default_agent(session_id)

    updated =
      existing
      |> maybe_update_from_event(event)
      |> Map.put(:last_event_at, DateTime.utc_now())
      |> Map.put(:status, derive_status(event, existing))
      |> then(&IdentityMerge.maybe_absorb_team_entry(session_id, &1))

    :ets.insert(@table, {session_id, updated})

    ensure_agent_process(session_id,
      role: updated.role || :worker,
      team: updated.team,
      backend: backend_from_channels(updated.channels)
    )

    broadcast_registry_update()
    state
  end

  defp maybe_register_event(false, _session_id, _event, state), do: state

  defp normalize_teams(t) when is_map(t), do: Map.values(t)
  defp normalize_teams(t) when is_list(t), do: t
  defp normalize_teams(_), do: []

  defp sweep_dead_teams(live_team_names) do
    :ets.tab2list(@table)
    |> Enum.each(fn {session_id, agent} ->
      sweep_if_dead_team(agent.team, live_team_names, session_id)
    end)
  end

  defp sweep_if_dead_team(nil, _live, _session_id), do: :ok

  defp sweep_if_dead_team(team, live_names, session_id) do
    case MapSet.member?(live_names, team) do
      true -> :ok
      false -> :ets.delete(@table, session_id)
    end
  end

  defp build_cwd_index do
    :ets.tab2list(@table)
    |> Enum.reduce(%{}, fn {key, agent}, acc ->
      case IdentityMerge.uuid?(key) && is_nil(agent.team) && agent.status == :active && agent.cwd do
        true -> Map.update(acc, agent.cwd, [{key, agent}], &[{key, agent} | &1])
        false -> acc
      end
    end)
  end

  defp sync_team_member(member, team_name, unaffiliated_by_cwd) do
    member_key = member[:agent_id] || member[:session_id]
    do_sync_member(member_key, member, team_name, unaffiliated_by_cwd)
  end

  defp do_sync_member(nil, _member, _team_name, _index), do: :ok

  defp do_sync_member(member_key, member, team_name, unaffiliated_by_cwd) do
    {canonical_key, existing} = IdentityMerge.find_canonical_entry(member_key, member, team_name, unaffiliated_by_cwd)

    tmux_target = resolve_tmux_target(member[:tmux_pane_id], existing.channels.tmux)

    updated_channels =
      existing.channels
      |> Map.put(:mailbox, canonical_key)
      |> Map.put(:tmux, tmux_target)

    qualified_id = IdentityMerge.qualify_agent_id(member[:name], team_name, canonical_key)

    updated =
      existing
      |> Map.put(:id, qualified_id)
      |> Map.put(:short_name, member[:name] || existing.id)
      |> Map.put(:team, team_name)
      |> Map.put(:role, derive_role(member[:agent_type]))
      |> Map.put(:model, member[:model] || existing.model)
      |> Map.put(:cwd, member[:cwd] || existing.cwd)
      |> Map.put(:channels, updated_channels)
      |> Map.put(:status, member_status(member[:is_active]))

    :ets.insert(@table, {canonical_key, updated})
    cleanup_orphan(canonical_key, member_key)
  end

  defp member_status(true), do: :active
  defp member_status(_), do: :ended

  defp cleanup_orphan(key, key), do: :ok
  defp cleanup_orphan(_canonical, member_key), do: :ets.delete(@table, member_key)

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

  def derive_role(nil), do: :standalone
  def derive_role("team-lead"), do: :lead
  def derive_role("lead"), do: :lead
  def derive_role("coordinator"), do: :coordinator
  def derive_role(_), do: :worker

  # Prefer tmux_pane_id from team config, fall back to existing channel value
  defp resolve_tmux_target(nil, existing), do: existing
  defp resolve_tmux_target("", existing), do: existing
  defp resolve_tmux_target(pane_id, _existing), do: pane_id

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

    live_teams = live_team_names()

    :ets.tab2list(@table)
    |> Enum.each(fn {session_id, agent} ->
      maybe_sweep(session_id, agent, live_teams, ended_cutoff, stale_cutoff)
    end)
  rescue
    ArgumentError -> :ok
  end

  defp live_team_names do
    Observatory.TeamWatcher.get_state() |> Map.keys() |> MapSet.new()
  rescue
    _ -> nil
  end

  # Never sweep the operator
  defp maybe_sweep(_sid, %{id: "operator"}, _live, _ended, _stale), do: :ok

  # Sweep agents from deleted teams
  defp maybe_sweep(sid, %{team: team}, live, _ended, _stale)
       when team != nil and live != nil do
    case MapSet.member?(live, team) do
      true -> :ok
      false -> :ets.delete(@table, sid)
    end
  end

  # Sweep ended agents after TTL
  defp maybe_sweep(sid, %{status: :ended, last_event_at: ts}, _live, ended_cutoff, _stale) do
    case DateTime.compare(ts, ended_cutoff) do
      :lt -> :ets.delete(@table, sid)
      _ -> :ok
    end
  end

  # Sweep infrastructure sessions and non-UUID standalones
  defp maybe_sweep(sid, %{role: :standalone, team: nil}, _live, _ended, stale_cutoff) do
    case {Observatory.Gateway.TmuxDiscovery.infrastructure_session?(sid), IdentityMerge.uuid?(sid)} do
      {true, _} -> :ets.delete(@table, sid)
      {_, false} -> :ets.delete(@table, sid)
      {_, true} -> maybe_sweep_stale(sid, stale_cutoff)
    end
  end

  defp maybe_sweep(_sid, _agent, _live, _ended, _stale), do: :ok

  defp maybe_sweep_stale(sid, stale_cutoff) do
    case :ets.lookup(@table, sid) do
      [{^sid, agent}] ->
        case DateTime.compare(agent.last_event_at, stale_cutoff) do
          :lt -> :ets.delete(@table, sid)
          _ -> :ok
        end

      [] ->
        :ok
    end
  end


  # ── BEAM Process Bridge ─────────────────────────────────────────────

  defp ensure_agent_process(id, opts) do
    case Observatory.Fleet.AgentProcess.alive?(id) do
      true ->
        :ok

      false ->
        process_opts = [
          id: id,
          role: opts[:role] || :worker,
          team: opts[:team],
          backend: opts[:backend]
        ]

        case Observatory.Fleet.FleetSupervisor.spawn_agent(process_opts) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} ->
            Logger.debug("[AgentRegistry] Could not start AgentProcess for #{id}: #{inspect(reason)}")
        end
    end
  rescue
    # FleetSupervisor may not be started yet during init
    _ -> :ok
  end

  defp backend_from_channels(%{tmux: session}) when is_binary(session) do
    %{type: :tmux, session: session}
  end

  defp backend_from_channels(%{ssh_tmux: address}) when is_binary(address) do
    %{type: :ssh_tmux, address: address}
  end

  defp backend_from_channels(%{webhook: url}) when is_binary(url) do
    %{type: :webhook, url: url}
  end

  defp backend_from_channels(_), do: nil
end
