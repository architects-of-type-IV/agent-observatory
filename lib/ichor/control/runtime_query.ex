defmodule Ichor.Control.RuntimeQuery do
  @moduledoc """
  Shared read-model queries over live teams, events, and task state.
  """

  alias Ichor.Control.Lookup
  alias Ichor.Tasks.TeamStore
  alias IchorWeb.Presentation

  @doc "Find the first team member map whose `:agent_id` matches `agent_id`."
  @spec find_team_member(list(), String.t()) :: map() | nil
  def find_team_member(teams, agent_id) do
    teams
    |> Enum.flat_map(& &1.members)
    |> Enum.find(&(&1[:agent_id] == agent_id))
  end

  @doc "Find a team member or synthesize a minimal agent entry from events for the given ID."
  @spec find_agent_entry(String.t(), list(), list()) :: map()
  def find_agent_entry(id, teams, events) do
    team_agent =
      teams
      |> Enum.flat_map(& &1.members)
      |> Enum.find(fn member -> member[:agent_id] == id || member[:name] == id end)

    team_agent || %{agent_id: id, name: find_session_name(events, id), session_id: id}
  end

  @doc "Find the in-progress task assigned to `agent_name` in the swarm state, or nil."
  @spec find_active_task(String.t() | nil, map() | any()) :: map() | nil
  def find_active_task(nil, _swarm), do: nil

  def find_active_task(agent_name, %{tasks: tasks}) when is_list(tasks) do
    Enum.find(tasks, fn task -> task.status == "in_progress" && task.owner == agent_name end)
  end

  def find_active_task(_agent_name, _swarm), do: nil

  @doc "Aggregate all tasks from the TeamStore for the given team list, tagged with team name."
  @spec list_tasks_for_teams(list()) :: list()
  def list_tasks_for_teams(teams) do
    Enum.flat_map(teams, fn team ->
      team.name
      |> TeamStore.list_tasks()
      |> Enum.map(&Map.put(&1, "team", team.name))
    end)
  end

  @doc "Serialize a team struct to a string-keyed map for JSON or LiveView rendering."
  @spec format_team(map()) :: map()
  def format_team(team) do
    %{
      "name" => team.name,
      "members" =>
        Enum.map(team.members, fn member ->
          %{
            "session_id" => member[:agent_id] || member[:session_id],
            "role" => member[:role] || member[:name],
            "status" => member[:status]
          }
        end),
      "member_count" => team.member_count,
      "health" => team.health,
      "source" => team.source
    }
  end

  defp find_session_name(events, session_id) do
    events
    |> Enum.find(&(&1.session_id == session_id))
    |> case do
      nil ->
        fallback_session_name(session_id)

      event ->
        event.tmux_session || fallback_session_name(session_id)
    end
  end

  defp fallback_session_name(session_id) do
    case Lookup.find_agent(session_id) do
      nil ->
        Presentation.short_id(session_id)

      agent ->
        agent[:name] || agent["name"] || Lookup.agent_session_id(agent) ||
          Presentation.short_id(session_id)
    end
  end
end
