defmodule Ichor.Infrastructure.Operations do
  @moduledoc """
  Action-only infrastructure surface for system and tmux operations.
  """

  use Ash.Resource, domain: Ichor.Infrastructure

  alias Ichor.AgentWatchdog
  alias Ichor.Infrastructure.Tmux
  alias Ichor.Signals.EventStream
  alias Ichor.Signals.ProtocolTracker
  alias Ichor.Workshop.{ActiveTeam, Agent}

  actions do
    action :system_health, :map do
      description("Check Ichor system health: agents, teams, and core runtime processes.")

      run(fn _input, _context ->
        agents = Agent.all!()
        teams = ActiveTeam.alive!()

        {:ok,
         %{
           "agents" => length(agents),
           "active_agents" => Enum.count(agents, fn agent -> agent.status == :active end),
           "teams" => length(teams),
           "event_buffer" => alive?(EventStream),
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
          Agent.all!()
          |> Enum.filter(fn agent -> agent.channels[:tmux] != nil end)
          |> Enum.group_by(fn agent -> agent.channels[:tmux] end)

        {:ok,
         Enum.map(sessions, fn session ->
           agents = Map.get(agents_by_tmux, session, [])

           %{
             "session" => session,
             "agents" =>
               Enum.map(agents, fn agent ->
                 %{
                   "id" => agent.agent_id,
                   "name" => agent.short_name || agent.name || agent.agent_id,
                   "team" => agent.team_name
                 }
               end)
           }
         end)}
      end)
    end

    action :sweep, :map do
      description(
        "Trigger an immediate registry sweep. Currently a no-op because the registry self-cleans."
      )

      run(fn _input, _context ->
        {:ok, %{"swept" => false, "message" => "no sweep needed"}}
      end)
    end
  end

  defp alive?(name), do: Process.whereis(name) != nil
end
