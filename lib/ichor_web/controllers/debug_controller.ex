defmodule IchorWeb.DebugController do
  @moduledoc "System diagnostics endpoint for quick debugging."
  use IchorWeb, :controller

  alias Ichor.Control
  alias Ichor.EventBuffer
  alias Ichor.Fleet.AgentProcess
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Gateway.HITLRelay
  alias Ichor.Observability
  alias Ichor.ProtocolTracker
  alias Ichor.Signals.Buffer

  def registry(conn, _params) do
    agents =
      AgentProcess.list_all()
      |> Enum.map(fn {id, meta} ->
        %{
          id: id,
          short_name: meta[:short_name],
          session_id: meta[:session_id] || id,
          team: meta[:team],
          role: meta[:role],
          status: meta[:status],
          model: meta[:model],
          cwd: meta[:cwd],
          current_tool: meta[:current_tool],
          channels: meta[:channels],
          last_event_at: meta[:last_event_at]
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
    agents = AgentProcess.list_all()

    %{
      ok: true,
      count: length(agents),
      has_operator: Enum.any?(agents, fn {id, _} -> id == "operator" end)
    }
  rescue
    e -> %{ok: false, error: Exception.message(e)}
  end

  defp check_team_watcher do
    teams = Control.list_alive_teams()
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
    process_agents = AgentProcess.list_all()
    %{ok: true, agent_processes: length(process_agents)}
  rescue
    e -> %{ok: false, error: Exception.message(e)}
  end

  defp check_event_buffer do
    if Process.whereis(EventBuffer) do
      %{ok: true, pid: inspect(Process.whereis(EventBuffer))}
    else
      %{ok: false, error: "EventBuffer not running"}
    end
  rescue
    e -> %{ok: false, error: Exception.message(e)}
  end

  def traces(conn, params) do
    traces = ProtocolTracker.get_traces()
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
          hops:
            Enum.map(t.hops, fn h ->
              %{protocol: h.protocol, status: h.status, at: h.at, detail: h.detail}
            end)
        }
      end)

    stats = ProtocolTracker.get_stats()

    json(conn, %{count: length(filtered), total: length(traces), stats: stats, traces: filtered})
  end

  def mailboxes(conn, _params) do
    messages =
      Observability.list_recent_messages()
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
    agents = Control.list_agents()

    events = EventBuffer.list_events()
    event_sessions = events |> Enum.map(& &1.session_id) |> Enum.uniq()

    beam_processes = AgentProcess.list_all() |> Enum.map(fn {id, _} -> id end)

    registry = AgentProcess.list_all() |> Enum.map(fn {id, _} -> id end)

    json(conn, %{
      count: length(agents),
      agents:
        Enum.map(agents, fn a ->
          %{
            agent_id: a.agent_id,
            name: a.name,
            status: a.status,
            team: a.team_name,
            session_id: a.session_id,
            cwd: a.cwd,
            source_app: a.source_app,
            subagent_count: length(a.subagents),
            subagents:
              Enum.map(a.subagents, fn s ->
                %{description: s[:description], type: s[:type], status: s[:status]}
              end)
          }
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

  def hitl_clear(conn, _params) do
    paused = HITLRelay.paused_sessions()
    Enum.each(paused, &HITLRelay.unpause(&1, "system", "debug-clear"))
    json(conn, %{cleared: length(paused), sessions: paused})
  end

  def purge(conn, _params) do
    # With Ichor.Registry as source of truth, stale cleanup is process-death-driven.
    # Return a no-op response for API compatibility.
    remaining = length(AgentProcess.list_all())
    json(conn, %{purged: 0, remaining: remaining})
  end

  def mes_cleanup(conn, _params) do
    alias Ichor.Fleet.{FleetSupervisor, TeamSupervisor}

    before = Enum.map(TeamSupervisor.list_all(), &elem(&1, 0))
    mes_teams = Enum.filter(before, &String.starts_with?(&1, "mes-"))

    results =
      Enum.map(mes_teams, fn name ->
        result = FleetSupervisor.disband_team(name)
        %{team: name, result: inspect(result), exists_after: TeamSupervisor.exists?(name)}
      end)

    after_teams = Enum.map(TeamSupervisor.list_all(), &elem(&1, 0))
    json(conn, %{before: before, results: results, after: after_teams})
  end

  def mes_signals(conn, _params) do
    signals =
      Buffer.recent(200)
      |> Enum.filter(fn s ->
        topic = Map.get(s, :topic, "")
        String.contains?(topic, "mes")
      end)
      |> Enum.take(50)
      |> Enum.map(fn s ->
        %{topic: s[:topic], shape: s[:shape], summary: s[:summary], at: s[:at]}
      end)

    json(conn, %{count: length(signals), signals: signals})
  end

  def tmux(conn, _params) do
    sessions = Tmux.list_sessions()
    panes = Tmux.list_panes()
    socket_args = Tmux.socket_args()

    # Show which registry agents have tmux channels wired
    agents_with_tmux =
      AgentProcess.list_all()
      |> Enum.filter(fn {_id, meta} -> get_in(meta, [:channels, :tmux]) != nil end)
      |> Enum.map(fn {id, meta} ->
        tmux = get_in(meta, [:channels, :tmux])

        %{
          id: id,
          session_id: meta[:session_id] || id,
          team: meta[:team],
          tmux_target: tmux,
          available: Tmux.available?(tmux)
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
      [:gateway_agent_registry, :ichor_tool_starts]
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
