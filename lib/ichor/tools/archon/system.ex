defmodule Ichor.Tools.Archon.System do
  @moduledoc """
  System diagnostics tools for Archon. Health checks and tmux state.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.{AgentWatchdog, EventBuffer, ProtocolTracker}
  alias Ichor.Control
  alias Ichor.Gateway.Channels.Tmux

  actions do
    action :system_health, :map do
      description("Check Ichor system health: agents, teams, core processes.")

      run(fn _input, _context ->
        agents = Control.list_agents()
        teams = Control.list_alive_teams()

        {:ok,
         %{
           "agents" => length(agents),
           "active_agents" => Enum.count(agents, fn a -> a.status == :active end),
           "teams" => length(teams),
           "event_buffer" => alive?(EventBuffer),
           "heartbeat" => alive?(AgentWatchdog),
           "protocol_tracker" => alive?(ProtocolTracker)
         }}
      end)
    end

    action :tmux_sessions, {:array, :map} do
      description("List active tmux sessions and which agents are connected to them.")

      run(fn _input, _context ->
        sessions = Tmux.list_sessions()

        agents_by_tmux =
          Control.list_agents()
          |> Enum.filter(fn a -> a.channels[:tmux] != nil end)
          |> Enum.group_by(fn a -> a.channels[:tmux] end)

        result =
          Enum.map(sessions, fn s ->
            agents = Map.get(agents_by_tmux, s, [])

            %{
              "session" => s,
              "agents" =>
                Enum.map(agents, fn a ->
                  %{
                    "id" => a.agent_id,
                    "name" => a.short_name || a.name || a.agent_id,
                    "team" => a.team_name
                  }
                end)
            }
          end)

        {:ok, result}
      end)
    end
  end

  defp alive?(name), do: Process.whereis(name) != nil
end
