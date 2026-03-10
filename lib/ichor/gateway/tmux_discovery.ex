defmodule Ichor.Gateway.TmuxDiscovery do
  @moduledoc """
  Polls tmux sessions and enforces the BEAM invariant:
  every non-infrastructure tmux session MUST have a BEAM AgentProcess.

  Continuously discovers tmux sessions, ensures BEAM processes exist,
  and enriches agents with tmux channel info. Runs every 5 seconds.
  """

  use GenServer
  require Logger

  alias Ichor.Gateway.AgentRegistry
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Fleet.AgentProcess
  alias Ichor.Fleet.FleetSupervisor

  @poll_interval 5_000

  # ── Client API ───────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    schedule_poll()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    poll()
    schedule_poll()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ─────────────────────────────────────────────────────────

  defp poll do
    tmux_sessions = Tmux.list_sessions()
    tmux_panes = Tmux.list_panes()
    all_agents = AgentRegistry.list_all_raw()

    ensure_beam_processes(tmux_sessions)
    enrich_tmux_channels(tmux_sessions, tmux_panes, all_agents)

    AgentRegistry.broadcast_update()
  end

  # Enforce the invariant: every agent tmux session has a BEAM process.
  # No filtering by naming convention — if it's not infrastructure, it's an agent.
  defp ensure_beam_processes(tmux_sessions) do
    for session_name <- tmux_sessions,
        not infrastructure_session?(session_name),
        not AgentProcess.alive?(session_name) do
      cwd = detect_cwd(session_name)
      create_agent_process(session_name, cwd)
    end
  end

  defp create_agent_process(session_name, cwd) do
    process_opts = [
      id: session_name,
      role: :worker,
      backend: %{type: :tmux, session: session_name},
      metadata: %{cwd: cwd, source: :tmux_discovery}
    ]

    case FleetSupervisor.spawn_agent(process_opts) do
      {:ok, _pid} ->
        Logger.info("[TmuxDiscovery] Created BEAM process for tmux session #{session_name}")

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.debug("[TmuxDiscovery] Failed to create process for #{session_name}: #{inspect(reason)}")
    end
  rescue
    _ -> :ok
  end

  defp detect_cwd(session_name) do
    case Tmux.run_command(["display-message", "-t", session_name, "-p", "\#{pane_current_path}"]) do
      {:ok, output} -> String.trim(output)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp enrich_tmux_channels(tmux_sessions, tmux_panes, all_entries) do
    Enum.each(all_entries, fn {session_id, agent} ->
      current_tmux = agent.channels.tmux

      unless current_tmux && target_alive?(current_tmux, tmux_sessions, tmux_panes) do
        matched = find_target(agent, tmux_sessions, tmux_panes)

        if matched && matched != current_tmux do
          AgentRegistry.update_tmux_channel(session_id, matched)
        end
      end
    end)
  end

  defp find_target(agent, sessions, panes) do
    exact = Enum.find(sessions, &(&1 == agent.id))

    if exact do
      exact
    else
      Enum.find(sessions, fn s ->
        String.starts_with?(s, agent.id) or String.contains?(s, agent.id)
      end) ||
        Enum.find_value(panes, fn p ->
          if String.contains?(p.title || "", agent.id), do: p.pane_id
        end)
    end
  end

  defp target_alive?(target, sessions, panes) do
    target in sessions or Enum.any?(panes, &(&1.pane_id == target))
  end

  @doc "Returns true for tmux server infrastructure sessions (not agents)."
  def infrastructure_session?("obs"), do: true
  def infrastructure_session?(name), do: match?({_, ""}, Integer.parse(name))

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end
end
