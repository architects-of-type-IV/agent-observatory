defmodule Ichor.Gateway.TmuxDiscovery do
  @moduledoc """
  Polls tmux sessions and wires them to the agent registry.
  Discovers new tmux sessions, auto-registers unknown ones,
  and enriches existing agents with tmux channel info.
  """

  use GenServer
  require Logger

  alias Ichor.Gateway.AgentRegistry
  alias Ichor.Gateway.Channels.Tmux

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

    register_unknown_sessions(tmux_sessions, all_agents)
    enrich_tmux_channels(tmux_sessions, tmux_panes, all_agents)

    AgentRegistry.broadcast_update()
  end

  defp register_unknown_sessions(tmux_sessions, all_entries) do
    known_ids = all_entries |> Enum.map(fn {_sid, a} -> a.id end) |> MapSet.new()

    known_tmux_targets =
      all_entries
      |> Enum.flat_map(fn {_sid, a} ->
        case a.channels.tmux do
          nil -> []
          target -> [target]
        end
      end)
      |> MapSet.new()

    for session_name <- tmux_sessions,
        not infrastructure_session?(session_name),
        not MapSet.member?(known_ids, session_name),
        not MapSet.member?(known_tmux_targets, session_name),
        is_nil(AgentRegistry.get(session_name)) do
      AgentRegistry.register_tmux_session(session_name)
    end
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

  @doc "Returns true for Ichor infrastructure tmux sessions that should be ignored."
  def infrastructure_session?("obs"), do: true
  def infrastructure_session?("obs-" <> _), do: true
  def infrastructure_session?(name), do: match?({_, ""}, Integer.parse(name))

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end
end
