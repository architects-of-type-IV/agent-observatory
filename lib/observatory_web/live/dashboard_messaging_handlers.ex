defmodule ObservatoryWeb.DashboardMessagingHandlers do
  @moduledoc """
  LiveView event handlers for messaging functionality in the Observatory Dashboard.
  All outbound messages route through Observatory.Operator for unified delivery.
  """

  def dispatch("search_messages", p, s), do: handle_search_messages(p, s)
  def dispatch("toggle_thread", p, s), do: handle_toggle_thread(p, s)
  def dispatch("expand_all_threads", _p, s), do: handle_expand_all_threads(s)
  def dispatch("collapse_all_threads", _p, s), do: handle_collapse_all_threads(s)

  def handle_send_agent_message(%{"content" => ""}, socket), do: {:noreply, socket}

  def handle_send_agent_message(%{"session_id" => sid, "content" => content}, socket) do
    case Observatory.Operator.send(sid, content) do
      {:ok, delivered} when delivered > 0 ->
        label = resolve_label(sid, socket)

        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Sent to #{label}",
            type: "success"
          })

        {:noreply, socket}

      {:ok, 0} ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "No delivery channel found",
            type: "warning"
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

  def handle_send_team_broadcast(%{"team" => team_name, "content" => content}, socket) do
    case Observatory.Operator.send("team:#{team_name}", content) do
      {:ok, delivered} ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Sent to #{team_name} (#{delivered} delivered)",
            type: "success"
          })

        {:noreply, socket}

      {:error, _reason} ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Failed to broadcast to #{team_name}",
            type: "error"
          })

        {:noreply, socket}
    end
  end

  def handle_push_context(%{"session_id" => sid, "file_path" => path}, socket) do
    case File.read(path) do
      {:ok, content} ->
        Observatory.Operator.send(sid, content, type: :context_push, metadata: %{file_path: path})
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_new_mailbox_message(_message, socket) do
    {:noreply, socket |> refresh_mailbox_assigns() |> Phoenix.Component.assign(:dirty, true)}
  end

  def refresh_mailbox_assigns(socket) do
    # Unread counts will be driven by PubSub message events in Phase 2.
    # AgentProcess.get_unread is destructive (clears on read), so we don't
    # poll it from the dashboard. The comms timeline shows messages in real-time.
    socket
  end

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

    socket
    |> Phoenix.Component.assign(:collapsed_threads, Map.put(collapsed_threads, key, new_state))
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

  defp resolve_label(sid, socket) do
    case Enum.find(socket.assigns[:sessions] || [], fn s -> s.session_id == sid end) do
      %{name: name} when is_binary(name) -> name
      _ -> String.slice(sid, 0..7)
    end
  end
end
