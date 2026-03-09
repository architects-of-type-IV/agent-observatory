defmodule Ichor.Gateway.AgentRegistry do
  @moduledoc """
  Unified fleet registry. Tracks all known agents, their status, team membership,
  and available delivery channels via a public ETS table.

  Delegates complex logic to focused submodules:
  - `AgentEntry` -- agent map construction and shared utilities
  - `EventHandler` -- hook event -> agent state transformation
  - `IdentityMerge` -- CWD-based identity correlation
  - `TeamSync` -- TeamWatcher data merge
  - `Sweep` -- stale entry garbage collection
  """

  use GenServer
  require Logger

  alias Ichor.Gateway.AgentRegistry.{AgentEntry, EventHandler, IdentityMerge, Sweep, TeamSync}

  @table :gateway_agent_registry
  @ended_ttl_seconds 1_800
  @stale_ttl_seconds 3_600

  # ── Client API ───────────────────────────────────────────────────────

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Register or update an agent from a hook event."
  def register_from_event(event), do: GenServer.cast(__MODULE__, {:register_event, event})

  @doc "Update agent info from TeamWatcher data."
  def sync_teams(teams), do: GenServer.cast(__MODULE__, {:sync_teams, teams})

  @doc "Mark an agent as ended."
  def mark_ended(session_id), do: GenServer.cast(__MODULE__, {:mark_ended, session_id})

  @doc "Remove an agent from the registry entirely. Blocks re-registration from hook events."
  def remove(session_id) do
    GenServer.cast(__MODULE__, {:dismiss, session_id})
    :ets.delete(@table, session_id)
    broadcast_update()
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Purge all stale/ended agents immediately. Returns count of purged entries."
  def purge_stale, do: GenServer.call(__MODULE__, :purge_stale)

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
      AgentEntry.new(session_name)
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
        :ets.insert(@table, {session_id, %{agent | channels: Map.put(agent.channels, :tmux, tmux_target)}})

      [] ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @doc "Update last_event_at timestamp (activity signal from pane monitor)."
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

  @doc "Register a spawned agent with optional parent tracking."
  def register_spawned(session_id, opts) do
    agent =
      AgentEntry.new(session_id)
      |> Map.merge(%{
        id: opts[:name] || AgentEntry.short_id(session_id),
        short_name: opts[:name] || AgentEntry.short_id(session_id),
        role: opts[:role] || :worker,
        team: opts[:team],
        cwd: opts[:cwd],
        host: opts[:host] || "local",
        parent_id: opts[:parent_id]
      })
      |> update_in([:channels], &Map.merge(&1, opts[:channels] || %{}))

    :ets.insert(@table, {session_id, agent})
    broadcast_update()
    agent
  rescue
    ArgumentError -> nil
  end

  @doc "Broadcast a registry change notification."
  def broadcast_update do
    Phoenix.PubSub.broadcast(Ichor.PubSub, "gateway:registry", :registry_changed)
  end

  # ── Query Helpers (pure, no ETS) ─────────────────────────────────

  @doc "Build a lookup map keyed by all known identifiers. Active agents win ties."
  def build_lookup(agents) do
    agents
    |> Enum.flat_map(fn a ->
      [a.id, a.session_id, a.short_name]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&{&1, a})
    end)
    |> dedup_by_status()
  end

  @doc "Dedup `{key, entry}` pairs: active entries win over non-active."
  def dedup_by_status(pairs) do
    Enum.reduce(pairs, %{}, fn {k, entry}, acc ->
      case Map.get(acc, k) do
        nil -> Map.put(acc, k, entry)
        %{status: :active} -> acc
        _existing -> Map.put(acc, k, entry)
      end
    end)
  end

  @doc "Find agents matching a channel pattern (agent:, session:, team:, role:, fleet:)."
  def resolve_channel(pattern) do
    case parse_channel(pattern) do
      {:agent, name} -> find_by_name_or_session(name)
      {:session, sid} -> List.wrap(get(sid))
      {:team, team} -> Enum.filter(list_all(), &(&1.team == team))
      {:role, role} -> Enum.filter(list_all(), &(&1.role == AgentEntry.role_from_string(role)))
      {:fleet, _} -> Enum.filter(list_all(), &(&1.status == :active))
      :unknown -> []
    end
  end

  @doc "Map a role string to an atom. Delegates to AgentEntry.role_from_string/1."
  defdelegate derive_role(str), to: AgentEntry, as: :role_from_string

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])

    operator =
      AgentEntry.new("operator")
      |> Map.merge(%{id: "operator", role: :operator, status: :active})
      |> Map.put(:channels, %{tmux: nil, mailbox: "operator", webhook: nil})

    :ets.insert(@table, {"operator", operator})

    Phoenix.PubSub.subscribe(Ichor.PubSub, "teams:update")
    Process.send_after(self(), :ensure_operator_process, 1_000)

    {:ok, %{dismissed: MapSet.new()}}
  end

  @impl true
  def handle_cast({:register_event, %{session_id: session_id} = event}, state) do
    unless MapSet.member?(state.dismissed, session_id) do
      register_hook_event(AgentEntry.uuid?(session_id), session_id, event)
    end

    {:noreply, state}
  end

  def handle_cast({:dismiss, session_id}, state) do
    {:noreply, %{state | dismissed: MapSet.put(state.dismissed, session_id)}}
  end

  def handle_cast({:sync_teams, teams}, state) do
    TeamSync.sync(teams)
    broadcast_update()
    {:noreply, state}
  end

  def handle_cast({:mark_ended, session_id}, state) do
    case get(session_id) do
      nil -> :ok
      agent -> :ets.insert(@table, {session_id, %{agent | status: :ended}})
    end

    broadcast_update()
    {:noreply, state}
  end

  @impl true
  def handle_call(:purge_stale, _from, state) do
    before = :ets.info(@table, :size)
    Sweep.run(@ended_ttl_seconds, @stale_ttl_seconds)
    after_count = :ets.info(@table, :size)
    broadcast_update()

    live_ids = :ets.tab2list(@table) |> Enum.map(fn {sid, _} -> sid end) |> MapSet.new()
    pruned_dismissed = MapSet.intersection(state.dismissed, live_ids)

    {:reply, {:ok, before - after_count}, %{state | dismissed: pruned_dismissed}}
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

  # ── Private ────────────────────────────────────────────────────────

  defp register_hook_event(false, _session_id, _event), do: :ok

  defp register_hook_event(true, session_id, event) do
    updated =
      (get(session_id) || AgentEntry.new(session_id))
      |> EventHandler.apply_event(event)
      |> then(&IdentityMerge.maybe_absorb_team_entry(session_id, &1))

    :ets.insert(@table, {session_id, updated})

    ensure_agent_process(session_id,
      role: updated.role || :worker,
      team: updated.team,
      backend: backend_from_channels(updated.channels)
    )

    broadcast_update()
  end

  defp ensure_agent_process(id, opts) do
    case Ichor.Fleet.AgentProcess.alive?(id) do
      true ->
        :ok

      false ->
        process_opts = [id: id, role: opts[:role] || :worker, team: opts[:team], backend: opts[:backend]]

        case Ichor.Fleet.FleetSupervisor.spawn_agent(process_opts) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> Logger.debug("[AgentRegistry] AgentProcess failed for #{id}: #{inspect(reason)}")
        end
    end
  rescue
    _ -> :ok
  end

  defp parse_channel("agent:" <> name), do: {:agent, name}
  defp parse_channel("session:" <> sid), do: {:session, sid}
  defp parse_channel("team:" <> name), do: {:team, name}
  defp parse_channel("role:" <> role), do: {:role, role}
  defp parse_channel("fleet:" <> rest), do: {:fleet, rest}
  defp parse_channel(_), do: :unknown

  defp find_by_name_or_session(name) do
    case get(name) do
      nil ->
        Enum.filter(list_all(), fn a ->
          a.id == name or a.short_name == name or a.session_id == name
        end)

      agent ->
        [agent]
    end
  end

  defp backend_from_channels(%{tmux: session}) when is_binary(session), do: %{type: :tmux, session: session}
  defp backend_from_channels(%{ssh_tmux: address}) when is_binary(address), do: %{type: :ssh_tmux, address: address}
  defp backend_from_channels(%{webhook: url}) when is_binary(url), do: %{type: :webhook, url: url}
  defp backend_from_channels(_), do: nil
end
