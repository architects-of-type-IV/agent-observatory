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
        # Get agent name from session
        agent_name =
          socket.assigns[:sessions]
          |> Enum.find(fn s -> s.session_id == sid end)
          |> case do
            %{name: name} -> name
            _ -> String.slice(sid, 0..7)
          end

        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Message sent to #{agent_name}",
            type: "success"
          })

        {:noreply, socket}

      {:error, _reason} ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Failed to send message",
            type: "error"
          })

        {:noreply, socket}
    end
  end

  @doc """
  Handle sending a broadcast to a team.
  """
  def handle_send_team_broadcast(%{"team" => team_name, "content" => content}, socket) do
    from_session = socket.assigns[:current_session_id] || "dashboard"

    # Publish via PubSub
    Observatory.Channels.publish_to_team(team_name, %{
      from: from_session,
      content: content,
      timestamp: DateTime.utc_now()
    })

    # Write broadcast command to each team member's inbox
    team_members = get_team_members(socket, team_name)

    Enum.each(team_members, fn member ->
      Observatory.CommandQueue.write_command(member.session_id, %{
        type: "broadcast",
        team: team_name,
        from: from_session,
        content: content
      })
    end)

    socket =
      Phoenix.LiveView.push_event(socket, "toast", %{
        message: "Broadcast sent to #{team_name} (#{length(team_members)} agents)",
        type: "success"
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
        # Send via mailbox (which now also writes to CommandQueue)
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

  def handle_search_messages(%{"q" => q}, socket) do
    socket |> Phoenix.Component.assign(:search_messages, q)
  end

  def handle_toggle_thread(%{"key" => key}, socket) do
    collapsed_threads = socket.assigns.collapsed_threads
    new_state = !Map.get(collapsed_threads, key, false)
    socket |> Phoenix.Component.assign(:collapsed_threads, Map.put(collapsed_threads, key, new_state))
  end

  def handle_expand_all_threads(socket) do
    socket |> Phoenix.Component.assign(:collapsed_threads, %{})
  end

  def handle_collapse_all_threads(socket) do
    thread_keys =
      socket.assigns.message_threads
      |> Enum.map(&ObservatoryWeb.DashboardMessageHelpers.participant_key(&1.participants))

    collapsed_map = Map.new(thread_keys, fn k -> {k, true} end)
    socket |> Phoenix.Component.assign(:collapsed_threads, collapsed_map)
  end

  defp get_team_members(socket, team_name) do
    team = Enum.find(socket.assigns[:teams] || [], &(&1.name == team_name))

    case team do
      nil ->
        []

      %{members: members} ->
        members
        |> Enum.filter(& &1[:agent_id])
        |> Enum.map(fn m -> %{session_id: m[:agent_id]} end)
    end
  end
end
