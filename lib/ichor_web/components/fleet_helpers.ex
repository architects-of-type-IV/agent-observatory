defmodule IchorWeb.Components.FleetHelpers do
  @moduledoc """
  Pure functions for fleet tree rendering: comms filtering, name resolution,
  and timestamp formatting.
  """

  alias IchorWeb.Presentation

  @doc "Build a session_id -> display name map from teams and agents."
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

  def resolve_label(id, map), do: Map.get(map, id, Presentation.short_id(id))

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

  def format_timestamp(ts), do: Presentation.format_time(ts, "%H:%M:%S")
end
