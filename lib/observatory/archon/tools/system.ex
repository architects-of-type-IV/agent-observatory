defmodule Observatory.Archon.Tools.System do
  @moduledoc """
  System diagnostics tools for Archon. Health checks and tmux state.
  """
  use Ash.Resource, domain: Observatory.Archon.Tools

  alias Observatory.Fleet.Agent, as: FleetAgent
  alias Observatory.Fleet.Team, as: FleetTeam
  alias Observatory.Gateway.Channels.Tmux
  alias Observatory.{EventBuffer, Heartbeat, ProtocolTracker}

  actions do
    action :system_health, :map do
      description "Check Observatory system health: agents, teams, core processes."

      run fn _input, _context ->
        agents = FleetAgent.all!()
        teams = FleetTeam.alive!()

        {:ok, %{
          "agents" => length(agents),
          "active_agents" => Enum.count(agents, fn a -> a.status == :active end),
          "teams" => length(teams),
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
          FleetAgent.all!()
          |> Enum.filter(fn a -> a.channels[:tmux] != nil end)
          |> Enum.group_by(fn a -> a.channels[:tmux] end)

        result =
          Enum.map(sessions, fn s ->
            agents = Map.get(agents_by_tmux, s, [])

            %{
              "session" => s,
              "agents" => Enum.map(agents, fn a ->
                %{"id" => a.agent_id, "name" => a.short_name || a.name || a.agent_id, "team" => a.team_name}
              end)
            }
          end)

        {:ok, result}
      end
    end
  end

  defp alive?(name), do: Process.whereis(name) != nil
end
