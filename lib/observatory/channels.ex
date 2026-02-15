defmodule Observatory.Channels do
  @moduledoc """
  PubSub channel management for agent, team, and session communication.

  Channel topology:
  - "agent:{session_id}" - private mailbox per agent
  - "team:{team_name}" - team broadcast channel
  - "session:{session_id}" - session event stream
  - "dashboard:commands" - outbound commands from UI
  """

  require Logger

  @pubsub Observatory.PubSub

  # ═══════════════════════════════════════════════════════
  # Channel Subscriptions
  # ═══════════════════════════════════════════════════════

  @doc """
  Subscribe to an agent's mailbox channel.
  """
  def subscribe_agent(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, agent_channel(session_id))
  end

  @doc """
  Subscribe to a team broadcast channel.
  """
  def subscribe_team(team_name) do
    Phoenix.PubSub.subscribe(@pubsub, team_channel(team_name))
  end

  @doc """
  Subscribe to a session event stream.
  """
  def subscribe_session(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, session_channel(session_id))
  end

  @doc """
  Subscribe to dashboard commands (UI -> agents).
  """
  def subscribe_dashboard_commands do
    Phoenix.PubSub.subscribe(@pubsub, "dashboard:commands")
  end

  @doc """
  Unsubscribe from an agent channel.
  """
  def unsubscribe_agent(session_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, agent_channel(session_id))
  end

  @doc """
  Unsubscribe from a team channel.
  """
  def unsubscribe_team(team_name) do
    Phoenix.PubSub.unsubscribe(@pubsub, team_channel(team_name))
  end

  # ═══════════════════════════════════════════════════════
  # Publishing Messages
  # ═══════════════════════════════════════════════════════

  @doc """
  Publish a message to a specific agent's mailbox channel.
  """
  def publish_to_agent(session_id, message) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      agent_channel(session_id),
      {:agent_message, message}
    )
  end

  @doc """
  Publish a message to a team broadcast channel.
  """
  def publish_to_team(team_name, message) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      team_channel(team_name),
      {:team_broadcast, message}
    )
  end

  @doc """
  Publish a session event to the session stream.
  """
  def publish_session_event(session_id, event) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      session_channel(session_id),
      {:session_event, event}
    )
  end

  @doc """
  Publish a dashboard command.
  """
  def publish_dashboard_command(command) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "dashboard:commands",
      {:dashboard_command, command}
    )
  end

  @doc """
  Broadcast to all channels (agent, team, session).
  """
  def broadcast(channel, message) do
    Phoenix.PubSub.broadcast(@pubsub, channel, message)
  end

  # ═══════════════════════════════════════════════════════
  # Channel Management
  # ═══════════════════════════════════════════════════════

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

    # Subscribe team members to the team channel
    Enum.each(members, fn member ->
      if member[:agent_id] do
        subscribe_team(team_name)
      end
    end)

    :ok
  end

  # ═══════════════════════════════════════════════════════
  # Channel Name Helpers
  # ═══════════════════════════════════════════════════════

  defp agent_channel(session_id), do: "agent:#{session_id}"
  defp team_channel(team_name), do: "team:#{team_name}"
  defp session_channel(session_id), do: "session:#{session_id}"
end
