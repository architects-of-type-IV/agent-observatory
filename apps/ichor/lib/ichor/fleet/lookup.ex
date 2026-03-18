defmodule Ichor.Fleet.Lookup do
  @moduledoc """
  Shared lookup helpers for fleet agent and team projections.
  """

  alias Ichor.Fleet.Agent, as: FleetAgent

  @spec find_agent(String.t()) :: struct() | nil
  def find_agent(query) when is_binary(query) do
    FleetAgent.all!()
    |> Enum.find(fn agent ->
      agent.agent_id == query or agent.session_id == query or
        agent.short_name == query or agent.name == query
    end)
  end

  @spec agent_session_id(struct() | map() | nil) :: String.t() | nil
  def agent_session_id(nil), do: nil
  def agent_session_id(agent), do: agent.session_id || agent.agent_id

  @spec agent_display_name(struct() | map()) :: String.t() | nil
  def agent_display_name(agent), do: agent.short_name || agent.name || agent.agent_id
end
