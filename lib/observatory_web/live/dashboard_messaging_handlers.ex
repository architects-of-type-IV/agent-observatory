defmodule ObservatoryWeb.DashboardMessagingHandlers do
  @moduledoc """
  LiveView event handlers for messaging functionality in the Observatory Dashboard.
  Handles agent messages, team broadcasts, and mailbox updates.
  """

  @doc """
  Handle sending a message to a specific agent.
  """
  def handle_send_agent_message(%{"session_id" => sid, "content" => content}, socket) do
    from_session = socket.assigns[:current_session_id] || "dashboard"

    case Observatory.Mailbox.send_message(sid, from_session, content, type: :text) do
      {:ok, _message} ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @doc """
  Handle sending a broadcast to a team.
  """
  def handle_send_team_broadcast(%{"team" => team_name, "content" => content}, socket) do
    from_session = socket.assigns[:current_session_id] || "dashboard"

    Observatory.Channels.publish_to_team(team_name, %{
      from: from_session,
      content: content,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  @doc """
  Handle sending context (file contents) to an agent.
  """
  def handle_push_context(%{"session_id" => sid, "file_path" => path}, socket) do
    from_session = socket.assigns[:current_session_id] || "dashboard"

    case File.read(path) do
      {:ok, content} ->
        Observatory.Mailbox.send_message(
          sid,
          from_session,
          content,
          type: :context_push,
          metadata: %{file_path: path}
        )

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @doc """
  Handle incoming mailbox message notification.
  Updates the UI to show new messages.
  """
  def handle_new_mailbox_message(_message, socket) do
    # Refresh mailbox data in assigns
    {:noreply, socket |> refresh_mailbox_assigns()}
  end

  @doc """
  Refresh mailbox-related assigns (called after message events).
  """
  def refresh_mailbox_assigns(socket) do
    # Get unread counts for all active sessions
    sessions = socket.assigns[:sessions] || []

    mailbox_counts =
      sessions
      |> Enum.map(fn s ->
        {s.session_id, Observatory.Mailbox.unread_count(s.session_id)}
      end)
      |> Map.new()

    Phoenix.Component.assign(socket, :mailbox_counts, mailbox_counts)
  end

  @doc """
  Subscribe to agent mailbox channels for all active sessions.
  """
  def subscribe_to_mailboxes(sessions) do
    Enum.each(sessions, fn s ->
      Observatory.Channels.subscribe_agent(s.session_id)
    end)
  end
end
