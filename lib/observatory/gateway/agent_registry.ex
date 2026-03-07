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
  @sweep_interval :timer.hours(1)
  @ended_ttl_seconds 7_200

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
    schedule_sweep()
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

    for team <- teams_list, member <- team.members do
      session_id = member[:agent_id] || member[:session_id]

      if session_id do
        existing = get(session_id) || default_agent(session_id)

        updated =
          existing
          |> Map.put(:id, member[:name] || existing.id)
          |> Map.put(:team, team.name)
          |> Map.put(:role, derive_role(member[:agent_type]))
          |> Map.put(:model, member[:model] || existing.model)
          |> Map.put(:cwd, member[:cwd] || existing.cwd)
          |> Map.merge(%{channels: Map.merge(existing.channels, %{mailbox: session_id})})

        :ets.insert(@table, {session_id, updated})
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

  def handle_info(:sweep, state) do
    sweep_ended_agents()
    new_capture = sweep_stale_captures(state.watched, state.last_capture)
    schedule_sweep()
    {:noreply, %{state | last_capture: new_capture}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ─────────────────────────────────────────────────────────

  defp default_agent(session_id) do
    %{
      id: short_id(session_id),
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
    known_ids = :ets.tab2list(@table) |> Enum.map(fn {_sid, a} -> a.id end) |> MapSet.new()

    # Auto-register tmux sessions not yet in the registry
    for session_name <- tmux_sessions,
        not MapSet.member?(known_ids, session_name),
        is_nil(get(session_name)) do
      agent =
        default_agent(session_name)
        |> Map.put(:id, session_name)
        |> Map.put(:channels, %{tmux: session_name, mailbox: session_name, webhook: nil})

      :ets.insert(@table, {session_name, agent})
    end

    # Enrich existing entries with tmux channel info
    :ets.tab2list(@table)
    |> Enum.each(fn {session_id, agent} ->
      matched_tmux =
        Enum.find(tmux_sessions, fn s ->
          String.starts_with?(s, agent.id) or String.contains?(s, agent.id)
        end)

      if matched_tmux != agent.channels.tmux do
        updated_channels = Map.put(agent.channels, :tmux, matched_tmux)
        :ets.insert(@table, {session_id, %{agent | channels: updated_channels}})
      end
    end)

    broadcast_registry_update()
  end

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
    # Try exact session_id match first
    case get(name) do
      nil ->
        # Search by agent name (id field)
        list_all() |> Enum.filter(fn a -> a.id == name end)

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
      {:registry_update, list_all()}
    )
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end

  defp sweep_ended_agents do
    cutoff = DateTime.add(DateTime.utc_now(), -@ended_ttl_seconds, :second)

    :ets.tab2list(@table)
    |> Enum.each(fn {session_id, agent} ->
      if agent.status == :ended && DateTime.compare(agent.last_event_at, cutoff) == :lt do
        :ets.delete(@table, session_id)
      end
    end)
  rescue
    ArgumentError -> :ok
  end

  defp sweep_stale_captures(watched, last_capture) do
    Map.filter(last_capture, fn {sid, _} -> MapSet.member?(watched, sid) end)
  end
end
