defmodule Ichor.Tools.AgentControl do
  @moduledoc """
  Shared runtime control actions used by tool-facing Ash resources.
  """

  alias Ichor.Control.Lifecycle.AgentLaunch
  alias Ichor.Control.Lookup
  alias Ichor.Gateway.HITLRelay

  @doc "Spawn a new agent and return its session metadata."
  @spec spawn(map()) :: {:ok, map()} | {:error, term()}
  def spawn(opts) when is_map(opts) do
    case AgentLaunch.spawn(opts) do
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

  @doc "Stop an agent by agent_id or session query."
  @spec stop(String.t()) :: {:ok, map()}
  def stop(query) when is_binary(query) do
    case Lookup.find_agent(query) do
      nil ->
        {:ok, %{stopped: false, reason: "agent not found: #{query}"}}

      agent ->
        session = agent.tmux_session || agent.agent_id
        AgentLaunch.stop(session)
        {:ok, %{stopped: true, session: session, name: agent.name}}
    end
  end

  @doc "Pause an agent via HITL with an optional reason."
  @spec pause(String.t(), String.t()) :: {:ok, map()}
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

  @doc "Resume a paused agent and flush buffered messages."
  @spec resume(String.t()) :: {:ok, map()}
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
