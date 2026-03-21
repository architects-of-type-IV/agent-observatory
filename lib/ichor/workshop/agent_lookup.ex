defmodule Ichor.Workshop.AgentLookup do
  @moduledoc false

  alias Ichor.Infrastructure.AgentProcess
  alias Ichor.Infrastructure.FleetSupervisor
  alias Ichor.Infrastructure.TeamSupervisor

  @doc false
  @spec spawn_in_fleet(String.t() | nil, keyword()) :: {:ok, pid()} | {:error, term()}
  def spawn_in_fleet(nil, opts) do
    FleetSupervisor.spawn_agent(opts)
  end

  def spawn_in_fleet(team_name, opts) do
    if not TeamSupervisor.exists?(team_name) do
      FleetSupervisor.create_team(name: team_name)
    end

    TeamSupervisor.spawn_member(team_name, opts)
  end

  @doc false
  @spec find_agent(String.t()) :: map() | nil
  def find_agent(query) when is_binary(query) do
    AgentProcess.list_all()
    |> Enum.find_value(fn {id, meta} ->
      agent_id = meta[:session_id] || id
      name = meta[:short_name] || meta[:name] || id

      if agent_id == query or id == query or
           meta[:session_id] == query or meta[:short_name] == query or
           meta[:name] == query do
        build_agent_match(agent_id, name, meta)
      end
    end)
  end

  @doc false
  @spec build_agent_match(String.t(), String.t(), map()) :: map()
  def build_agent_match(agent_id, name, meta) do
    %{
      agent_id: agent_id,
      session_id: meta[:session_id] || agent_id,
      name: name,
      short_name: meta[:short_name],
      role: to_string(meta[:role] || :worker),
      model: meta[:model],
      status: meta[:status],
      cwd: meta[:cwd],
      current_tool: meta[:current_tool],
      last_event_at: meta[:last_event_at],
      tmux_session: get_in(meta, [:channels, :tmux]),
      channels: meta[:channels] || %{},
      team_name: meta[:team]
    }
  end
end
