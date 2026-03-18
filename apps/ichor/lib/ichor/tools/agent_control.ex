defmodule Ichor.Tools.AgentControl do
  @moduledoc """
  Shared runtime control actions used by tool-facing Ash resources.
  """

  alias Ichor.AgentSpawner
  alias Ichor.Fleet.Lookup
  alias Ichor.Gateway.HITLRelay

  def spawn(opts) when is_map(opts) do
    case AgentSpawner.spawn_agent(opts) do
      {:ok, result} ->
        {:ok,
         %{
           session_id: result[:agent_id] || result[:session_name],
           session_name: result[:session_name],
           agent_id: result[:agent_id],
           name: result[:name],
           team: result[:team_name],
           cwd: result[:cwd]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stop(query) when is_binary(query) do
    case Lookup.find_agent(query) do
      nil ->
        {:ok, %{stopped: false, reason: "agent not found: #{query}"}}

      agent ->
        session = agent.tmux_session || agent.agent_id
        AgentSpawner.stop_agent(session)
        {:ok, %{stopped: true, session: session, name: agent.name}}
    end
  end

  def pause(query, reason) when is_binary(query) do
    case Lookup.find_agent(query) do
      nil ->
        {:ok, %{paused: false, reason: "agent not found: #{query}"}}

      agent ->
        sid = Lookup.agent_session_id(agent)

        case HITLRelay.pause(sid, sid, "archon", reason) do
          :ok ->
            {:ok, %{paused: true, session_id: sid, name: agent.name}}

          {:ok, :already_paused} ->
            {:ok, %{paused: true, already_paused: true, session_id: sid}}
        end
    end
  end

  def resume(query) when is_binary(query) do
    case Lookup.find_agent(query) do
      nil ->
        {:ok, %{resumed: false, reason: "agent not found: #{query}"}}

      agent ->
        sid = Lookup.agent_session_id(agent)

        case HITLRelay.unpause(sid, sid, "archon") do
          {:ok, :not_paused} ->
            {:ok, %{resumed: false, reason: "agent was not paused"}}

          {:ok, flushed} ->
            {:ok, %{resumed: true, flushed_messages: flushed, session_id: sid}}
        end
    end
  end
end
