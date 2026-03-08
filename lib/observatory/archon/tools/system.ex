defmodule Observatory.Archon.Tools.System do
  @moduledoc """
  System diagnostics tools for Archon. Health checks and tmux state.
  """
  use Ash.Resource, domain: Observatory.Archon.Tools

  alias Observatory.Gateway.AgentRegistry
  alias Observatory.Gateway.Channels.Tmux
  alias Observatory.{TeamWatcher, EventBuffer, Heartbeat, ProtocolTracker}

  actions do
    action :system_health, :map do
      description "Check Observatory system health: agents, teams, core processes."

      run fn _input, _context ->
        agents = AgentRegistry.list_all()

        {:ok, %{
          "agents" => length(agents),
          "active_agents" => Enum.count(agents, fn a -> a.status == :active end),
          "teams" => map_size(TeamWatcher.get_state()),
          "event_buffer" => alive?(EventBuffer),
          "heartbeat" => alive?(Heartbeat),
          "protocol_tracker" => alive?(ProtocolTracker)
        }}
      end
    end

    action :tmux_sessions, {:array, :map} do
      description "List active tmux sessions and which agents are connected to them."

      run fn _input, _context ->
        sessions = Tmux.list_sessions()

        agents_by_tmux =
          AgentRegistry.list_all()
          |> Enum.filter(fn a -> a.channels.tmux != nil end)
          |> Enum.group_by(fn a -> a.channels.tmux end)

        result =
          Enum.map(sessions, fn s ->
            agents = Map.get(agents_by_tmux, s, [])

            %{
              "session" => s,
              "agents" => Enum.map(agents, fn a ->
                %{"id" => a.id, "name" => a[:short_name] || a.id, "team" => a.team}
              end)
            }
          end)

        {:ok, result}
      end
    end
  end

  defp alive?(name), do: Process.whereis(name) != nil
end
