defmodule ObservatoryWeb.DebugController do
  @moduledoc "System diagnostics endpoint for quick debugging."
  use ObservatoryWeb, :controller

  alias Observatory.Gateway.AgentRegistry

  def registry(conn, _params) do
    agents =
      AgentRegistry.list_all()
      |> Enum.map(fn a ->
        %{
          id: a.id,
          short_name: Map.get(a, :short_name),
          session_id: a.session_id,
          team: a.team,
          role: a.role,
          status: a.status,
          model: a.model,
          cwd: a.cwd,
          current_tool: a.current_tool,
          channels: a.channels,
          started_at: a.started_at,
          last_event_at: a.last_event_at
        }
      end)

    json(conn, %{count: length(agents), agents: agents})
  end

  def health(conn, _params) do
    checks = %{
      registry: check_registry(),
      team_watcher: check_team_watcher(),
      pubsub: check_pubsub(),
      mailbox: check_mailbox(),
      event_buffer: check_event_buffer(),
      ets_tables: check_ets_tables()
    }

    status = if Enum.all?(checks, fn {_k, v} -> v.ok end), do: :ok, else: :degraded

    json(conn, %{status: status, checks: checks})
  end

  defp check_registry do
    agents = AgentRegistry.list_all()
    %{ok: true, count: length(agents), has_operator: Enum.any?(agents, &(&1.id == "operator"))}
  rescue
    e -> %{ok: false, error: Exception.message(e)}
  end

  defp check_team_watcher do
    teams = Observatory.Fleet.Team.alive!()
    team_names = Enum.map(teams, & &1.name)
    member_count = Enum.reduce(teams, 0, fn t, acc -> acc + t.member_count end)
    %{ok: true, teams: team_names, member_count: member_count}
  rescue
    e -> %{ok: false, error: Exception.message(e)}
  end

  defp check_pubsub do
    node = node()
    %{ok: true, node: node}
  end

  defp check_mailbox do
    process_agents = Observatory.Fleet.AgentProcess.list_all()
    %{ok: true, agent_processes: length(process_agents)}
  rescue
    e -> %{ok: false, error: Exception.message(e)}
  end

  defp check_event_buffer do
    if Process.whereis(Observatory.EventBuffer) do
      %{ok: true, pid: inspect(Process.whereis(Observatory.EventBuffer))}
    else
      %{ok: false, error: "EventBuffer not running"}
    end
  rescue
    e -> %{ok: false, error: Exception.message(e)}
  end

  def traces(conn, params) do
    traces = Observatory.ProtocolTracker.get_traces()
    limit = String.to_integer(params["limit"] || "50")
    type_filter = params["type"]

    filtered =
      traces
      |> maybe_filter_type(type_filter)
      |> Enum.take(limit)
      |> Enum.map(fn t ->
        %{
          id: t.id,
          type: t.type,
          from: t.from,
          to: t.to,
          content_preview: t.content_preview,
          message_type: t.message_type,
          timestamp: t.timestamp,
          hops: Enum.map(t.hops, fn h ->
            %{protocol: h.protocol, status: h.status, at: h.at, detail: h.detail}
          end)
        }
      end)

    stats = Observatory.ProtocolTracker.get_stats()

    json(conn, %{count: length(filtered), total: length(traces), stats: stats, traces: filtered})
  end

  def mailboxes(conn, _params) do
    messages =
      Observatory.Activity.Message.recent!()
      |> Enum.take(50)
      |> Enum.map(fn m ->
        %{
          id: m.id,
          from: m.sender_session,
          to: m.recipient,
          content: String.slice(m.content || "", 0, 200),
          type: m.type,
          timestamp: m.timestamp
        }
      end)

    json(conn, %{count: length(messages), messages: messages})
  end

  def fleet_agents(conn, _params) do
    agents = Observatory.Fleet.Agent.all!()

    events = Observatory.EventBuffer.list_events()
    event_sessions = events |> Enum.map(& &1.session_id) |> Enum.uniq()

    beam_processes = Observatory.Fleet.AgentProcess.list_all() |> Enum.map(fn {id, _} -> id end)

    registry = Observatory.Gateway.AgentRegistry.list_all() |> Enum.map(& &1.session_id)

    json(conn, %{
      count: length(agents),
      agents: Enum.map(agents, fn a ->
        %{agent_id: a.agent_id, name: a.name, status: a.status, team: a.team_name,
          session_id: a.session_id, cwd: a.cwd, source_app: a.source_app}
      end),
      sources: %{
        event_buffer_sessions: event_sessions,
        beam_processes: beam_processes,
        registry: registry
      }
    })
  rescue
    e -> json(conn, %{error: Exception.message(e)})
  end

  def purge(conn, _params) do
    {:ok, purged} = AgentRegistry.purge_stale()
    remaining = length(AgentRegistry.list_all())
    json(conn, %{purged: purged, remaining: remaining})
  end

  def tmux(conn, _params) do
    alias Observatory.Gateway.Channels.Tmux

    sessions = Tmux.list_sessions()
    panes = Tmux.list_panes()
    socket_args = Tmux.socket_args()

    # Show which registry agents have tmux channels wired
    agents_with_tmux =
      AgentRegistry.list_all()
      |> Enum.filter(fn a -> a.channels.tmux != nil end)
      |> Enum.map(fn a ->
        %{
          id: a.id,
          session_id: a.session_id,
          team: a.team,
          tmux_target: a.channels.tmux,
          available: Tmux.available?(a.channels.tmux)
        }
      end)

    json(conn, %{
      socket_args: socket_args,
      sessions: sessions,
      panes: panes,
      agents_with_tmux: agents_with_tmux
    })
  end

  defp maybe_filter_type(traces, nil), do: traces
  defp maybe_filter_type(traces, type) do
    atom_type = String.to_existing_atom(type)
    Enum.filter(traces, &(&1.type == atom_type))
  rescue
    ArgumentError -> traces
  end

  defp check_ets_tables do
    tables =
      [:gateway_agent_registry, :observatory_tool_starts]
      |> Enum.map(fn name ->
        case :ets.info(name) do
          :undefined -> {name, %{exists: false}}
          info -> {name, %{exists: true, size: Keyword.get(info, :size, 0)}}
        end
      end)
      |> Map.new()

    %{ok: true, tables: tables}
  rescue
    e -> %{ok: false, error: Exception.message(e)}
  end
end
