defmodule Ichor.Archon.Tools.Events do
  @moduledoc """
  Event feed and task overview tools for Archon.
  Provides raw event stream access and fleet-wide task visibility.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.Control
  alias Ichor.EventBuffer
  alias Ichor.Fleet.Lookup
  alias Ichor.Fleet.RuntimeQuery

  actions do
    action :agent_events, {:array, :map} do
      description("Get recent hook events for a specific agent. Raw event stream.")

      argument :agent_id, :string do
        allow_nil?(false)
        description("Agent name, short name, or session ID")
      end

      argument :limit, :integer do
        allow_nil?(false)
        description("Number of events to return (default: 30)")
      end

      run(fn input, _context ->
        query = input.arguments.agent_id
        limit = Map.get(input.arguments, :limit) || 30

        agent = Lookup.find_agent(query)
        sid = Lookup.agent_session_id(agent) || query

        events =
          EventBuffer.list_events()
          |> Enum.filter(fn e -> e.session_id == sid end)
          |> Enum.take(limit)
          |> Enum.map(&format_event/1)

        {:ok, events}
      end)
    end

    action :fleet_tasks, {:array, :map} do
      description("List tasks across all teams, or for a specific team.")

      argument :team_name, :string do
        allow_nil?(false)
        description("Filter to a specific team (empty string for all teams)")
      end

      run(fn input, _context ->
        team_filter = Map.get(input.arguments, :team_name)

        teams =
          if team_filter in [nil, ""] do
            Control.list_alive_teams()
          else
            Control.list_alive_teams()
            |> Enum.filter(fn t -> t.name == team_filter end)
          end

        tasks =
          RuntimeQuery.list_tasks_for_teams(teams)

        {:ok, tasks}
      end)
    end
  end

  defp format_event(e) do
    %{
      "type" => e.hook_event_type,
      "tool" => e.tool_name,
      "at" => e.inserted_at,
      "summary" => e.summary,
      "cwd" => e.cwd
    }
  end
end
