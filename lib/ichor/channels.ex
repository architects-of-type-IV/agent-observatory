defmodule Ichor.Channels do
  @moduledoc """
  PubSub channel management for agent and team communication.

  Channel topology:
  - "agent:{session_id}" - private mailbox per agent
  - "team:{team_name}" - team broadcast channel

  Active functions:
  - subscribe_agent/1 - subscribed by DashboardMessagingHandlers
  - create_agent_channel/1 - called by Gateway.Router.EventIngest on session start
  - create_team_channel/2 - called by Gateway.Router.EventIngest on team creation
  """

  require Logger

  @pubsub Ichor.PubSub

  @doc """
  Subscribe to an agent's mailbox channel.
  """
  def subscribe_agent(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, agent_channel(session_id))
  end

  @doc """
  Create and initialize an agent channel (triggered by SessionStart).
  """
  def create_agent_channel(session_id) do
    Logger.debug("Creating agent channel: #{agent_channel(session_id)}")
    :ok
  end

  @doc """
  Create and initialize a team channel (triggered by TeamCreate).
  """
  def create_team_channel(team_name, members \\ []) do
    Logger.debug(
      "Creating team channel: #{team_channel(team_name)} with #{length(members)} members"
    )

    :ok
  end

  # Channel Name Helpers

  defp agent_channel(session_id), do: "agent:#{session_id}"
  defp team_channel(team_name), do: "team:#{team_name}"
end
