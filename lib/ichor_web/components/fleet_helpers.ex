defmodule IchorWeb.Components.FleetHelpers do
  @moduledoc """
  Pure functions for fleet tree rendering: role classification,
  hierarchy sorting, chain-of-command derivation, and comms filtering.
  """

  # -- Role classification --
  # Delegates to AgentRegistry.derive_role/1 for canonical agent_type mapping.
  # Adds map-based and name-heuristic overloads for display contexts.

  alias Ichor.Gateway.AgentRegistry
  alias Ichor.Gateway.AgentRegistry.AgentEntry

  def classify_role(%{role: r}) when is_atom(r), do: r

  def classify_role(%{role: r}) when is_binary(r),
    do: normalize_role(AgentRegistry.derive_role(r))

  def classify_role(%{"role" => r}) when is_binary(r),
    do: normalize_role(AgentRegistry.derive_role(r))

  def classify_role(name) when is_binary(name) do
    cond do
      String.contains?(name, "coordinator") -> :coordinator
      String.contains?(name, "lead") -> :lead
      String.contains?(name, "worker") -> :worker
      true -> :member
    end
  end

  def classify_role(_), do: :member

  defp normalize_role(:standalone), do: :member
  defp normalize_role(role), do: role

  def depth(:coordinator), do: 0
  def depth(:lead), do: 1
  def depth(:worker), do: 2
  def depth(_), do: 2

  def badge_class(:coordinator), do: "bg-brand-dim/50 text-brand border-brand/50"
  def badge_class(:lead), do: "bg-interactive/50 text-interactive border-interactive/50"
  def badge_class(:worker), do: "bg-raised text-default border-border-subtle/50"
  def badge_class(_), do: "bg-raised text-low border-border-subtle/50"

  def abbrev(:coordinator), do: "coord"
  def abbrev(:lead), do: "lead"
  def abbrev(:worker), do: "work"
  def abbrev(_), do: "member"

  # -- Hierarchy sorting --

  def sort_members(members, agent_index) when is_map(agent_index) do
    members
    |> Enum.map(fn m ->
      sid = m[:session_id] || m[:agent_id] || m["session_id"]
      agent = Map.get(agent_index, sid)
      role = classify_role(m[:name] || m[:agent_type] || m["name"])
      {m, agent, depth(role)}
    end)
    |> Enum.sort_by(fn {_m, _a, d} -> d end)
  end

  # -- Chain of command --

  def chain_of_command(member, sorted_members) do
    role = classify_role(member)
    my_depth = depth(role)
    sid = member[:session_id] || member["session_id"]
    reports_to = find_reports_to(my_depth, sorted_members)
    manages = find_manages(my_depth, sid, sorted_members)
    {reports_to, manages}
  end

  defp find_reports_to(0, _sorted_members), do: nil

  defp find_reports_to(my_depth, sorted_members) do
    case Enum.find(sorted_members, fn {_m, _a, d} -> d < my_depth end) do
      {m, _a, _d} -> m
      nil -> nil
    end
  end

  defp find_manages(my_depth, sid, sorted_members) do
    sorted_members
    |> Enum.filter(fn {_m, _a, d} -> d > my_depth end)
    |> Enum.reject(fn {m, _a, _d} -> (m[:session_id] || m["session_id"]) == sid end)
    |> Enum.map(fn {m, _a, _d} -> m end)
  end

  # -- Comms helpers --

  def name_map(teams, agents) do
    team_entries =
      for t <- teams,
          m <- Map.get(t, :members, []),
          sid = m[:session_id] || m["session_id"],
          sid != nil,
          into: %{} do
        {sid, m[:name] || m["name"] || sid}
      end

    agent_entries =
      for a <- agents, into: %{} do
        sid = a[:session_id] || a[:agent_id]
        {sid, a[:name] || a[:label] || sid}
      end

    agent_entries
    |> Map.merge(team_entries)
    |> Map.put("operator", "operator")
  end

  def resolve_label(id, map), do: Map.get(map, id, short_id(id))

  defp short_id(nil), do: "?"
  defp short_id(id), do: AgentEntry.short_id(id)

  def filter_by_team(messages, nil, _teams), do: messages

  def filter_by_team(messages, team_name, teams) do
    case Enum.find(teams, fn t -> t.name == team_name end) do
      nil ->
        messages

      t ->
        sids =
          Map.get(t, :members, [])
          |> Enum.map(fn m -> m[:session_id] || m["session_id"] end)
          |> MapSet.new()

        Enum.filter(messages, fn msg ->
          MapSet.member?(sids, msg.from) or
            MapSet.member?(sids, msg.to) or
            msg.from == "operator" or
            msg.to == "operator"
        end)
    end
  end

  @doc "Filter messages involving a specific agent (or pair when two agents specified)."
  def filter_by_agents(messages, nil, _), do: messages
  def filter_by_agents(messages, [], _), do: messages

  def filter_by_agents(messages, [agent_a], _names) do
    Enum.filter(messages, fn msg ->
      msg.from == agent_a or msg.to == agent_a
    end)
  end

  def filter_by_agents(messages, [agent_a, agent_b], _names) do
    Enum.filter(messages, fn msg ->
      (msg.from == agent_a and msg.to == agent_b) or
        (msg.from == agent_b and msg.to == agent_a)
    end)
  end

  def filter_by_agents(messages, _, _), do: messages

  def format_timestamp(nil), do: ""
  def format_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  def format_timestamp(_), do: ""

  # -- Project grouping --

  def group_teams_by_project(teams, agent_index \\ %{}) do
    teams
    |> Enum.group_by(fn t -> team_project(t, agent_index) end)
    |> Enum.sort_by(fn {project, _} -> project end)
  end

  defp team_project(team, agent_index) do
    # First try team members (Ash resource)
    from_members =
      Enum.find_value(team.members, nil, fn m ->
        cwd = m[:cwd] || get_in(agent_index, [m[:agent_id], :cwd])
        cwd && Path.basename(cwd)
      end)

    # Fallback: find any agent in agent_index belonging to this team
    from_members ||
      Enum.find_value(agent_index, "unknown", fn
        {_id, %{team: t, cwd: cwd}} when t == team.name and not is_nil(cwd) ->
          Path.basename(cwd)

        _ ->
          nil
      end)
  end
end
