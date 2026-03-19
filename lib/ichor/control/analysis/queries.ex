defmodule Ichor.Control.Analysis.Queries do
  @moduledoc """
  Pure query functions for fleet data derivation.
  Operates on raw events, teams, and sessions.
  """

  import IchorWeb.DashboardFormatHelpers, only: [session_duration_sec: 1]
  import IchorWeb.DashboardSessionHelpers, only: [short_model_name: 1]

  alias Ichor.Gateway.AgentRegistry.AgentEntry

  @doc """
  Derive active sessions from raw events and tmux sessions.
  """
  @spec active_sessions(list(), keyword()) :: list()
  def active_sessions(events, opts \\ []) do
    tmux_sessions = Keyword.get(opts, :tmux, [])
    now = Keyword.get(opts, :now, DateTime.utc_now())

    sessions =
      events
      |> Enum.group_by(&{&1.source_app, &1.session_id})
      |> Enum.map(fn {{app, sid}, evts} ->
        sorted = Enum.sort_by(evts, & &1.inserted_at, {:desc, DateTime})
        latest = hd(sorted)
        ended? = Enum.any?(evts, &(&1.hook_event_type == :SessionEnd))

        %{
          source_app: app,
          session_id: sid,
          event_count: length(evts),
          latest_event: latest,
          first_event: List.last(sorted),
          ended?: ended?,
          model: find_model(evts),
          permission_mode: latest.permission_mode,
          cwd: latest.cwd || find_cwd(evts)
        }
      end)
      |> Enum.sort_by(& &1.latest_event.inserted_at, {:desc, DateTime})

    sessions ++ build_tmux_only(events, tmux_sessions, now)
  end

  @doc """
  Compute topology nodes and edges from sessions and teams.
  """
  @spec topology(list(), list(), DateTime.t()) :: {list(), list()}
  def topology(all_sessions, teams, now) do
    team_member_index = build_team_member_index(teams)
    session_sids = MapSet.new(all_sessions, & &1.session_id)

    session_nodes = Enum.map(all_sessions, &session_node(&1, now, team_member_index))
    member_nodes = Enum.flat_map(teams, &team_member_nodes(&1, session_sids))
    topo_edges = Enum.flat_map(teams, &team_edges/1)

    {session_nodes ++ member_nodes, topo_edges}
  end

  defp build_team_member_index(teams) do
    teams
    |> Enum.flat_map(fn t ->
      Enum.map(t.members, fn m ->
        {m[:agent_id], %{team: t.name, role: m[:name] || m[:agent_type]}}
      end)
    end)
    |> Map.new()
  end

  defp session_node(s, now, team_member_index) do
    status =
      cond do
        s.ended? -> "dead"
        DateTime.diff(now, s.latest_event.inserted_at, :second) > 120 -> "idle"
        true -> "active"
      end

    team_info = Map.get(team_member_index, s.session_id, %{})
    dur = DateTime.diff(now, s.first_event.inserted_at, :second)

    %{
      trace_id: s.session_id,
      agent_id: s.session_id,
      state: status,
      label: team_info[:role] || s.source_app || AgentEntry.short_id(s.session_id),
      model: short_model_name(s.model),
      team: team_info[:team],
      events: s.event_count,
      cwd: if(s.cwd, do: Path.basename(s.cwd), else: nil),
      duration: session_duration_sec(dur)
    }
  end

  defp team_member_nodes(team, session_sids) do
    team.members
    |> Enum.filter(fn m -> m[:agent_id] && not MapSet.member?(session_sids, m[:agent_id]) end)
    |> Enum.map(fn m ->
      %{
        trace_id: m[:agent_id],
        agent_id: m[:agent_id],
        state: to_string(m[:status] || :idle),
        label: m[:name] || m[:agent_type] || AgentEntry.short_id(m[:agent_id] || ""),
        model: short_model_name(m[:model]),
        team: team.name,
        events: m[:event_count] || 0,
        cwd: if(m[:cwd], do: Path.basename(m[:cwd]), else: nil),
        duration: nil
      }
    end)
  end

  defp team_edges(team) do
    team.members
    |> Enum.map(& &1[:agent_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] ->
      %{from: from, to: to, traffic_volume: 0, latency_ms: 0, status: "active"}
    end)
  end

  defp build_tmux_only(events, tmux_sessions, now) do
    known_tmux =
      events
      |> Enum.map(& &1.tmux_session)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    tmux_sessions
    |> Enum.reject(fn name -> MapSet.member?(known_tmux, name) end)
    |> Enum.map(fn name ->
      %{
        source_app: name,
        session_id: name,
        event_count: 0,
        latest_event: %{inserted_at: now},
        first_event: %{inserted_at: now},
        ended?: false,
        model: nil,
        permission_mode: nil,
        cwd: nil,
        tmux_session: name
      }
    end)
  end

  defp find_model(events),
    do: Enum.find_value(events, fn e -> e.payload["model"] || e.model_name end)

  defp find_cwd(events), do: Enum.find_value(events, fn e -> e.cwd end)
end
