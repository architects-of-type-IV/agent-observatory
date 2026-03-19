defmodule IchorWeb.DashboardMessagingHandlers do
  @moduledoc """
  LiveView event handlers for messaging functionality in the Ichor Dashboard.
  All outbound messages route through Ichor.Operator for unified delivery.
  """

  def dispatch("set_message_target", p, s), do: handle_set_message_target(p, s)
  def dispatch("send_targeted_message", p, s), do: handle_send_targeted_message(p, s)

  def handle_send_agent_message(%{"content" => ""}, socket), do: {:noreply, socket}

  def handle_send_agent_message(%{"session_id" => sid, "content" => content}, socket) do
    case Ichor.Operator.send(sid, content) do
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
    end
  end

  def handle_send_team_broadcast(%{"team" => team_name, "content" => content}, socket) do
    case Ichor.Operator.send("team:#{team_name}", content) do
      {:ok, delivered} ->
        socket =
          Phoenix.LiveView.push_event(socket, "toast", %{
            message: "Sent to #{team_name} (#{delivered} delivered)",
            type: "success"
          })

        {:noreply, socket}
    end
  end

  def handle_push_context(%{"session_id" => sid, "file_path" => path}, socket) do
    case File.read(path) do
      {:ok, content} ->
        Ichor.Operator.send(sid, content, type: :context_push, metadata: %{file_path: path})
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_new_mailbox_message(_message, socket) do
    {:noreply, refresh_mailbox_assigns(socket)}
  end

  def refresh_mailbox_assigns(socket) do
    # Unread counts will be driven by PubSub message events in Phase 2.
    # AgentProcess.get_unread is destructive (clears on read), so we don't
    # poll it from the dashboard. The comms timeline shows messages in real-time.
    socket
  end

  def subscribe_to_mailboxes(sessions) do
    Enum.each(sessions, fn s ->
      Ichor.Channels.subscribe_agent(s.session_id)
    end)
  end

  def handle_set_message_target(%{"target" => target}, socket) do
    Phoenix.Component.assign(socket, :selected_message_target, target)
  end

  def handle_send_targeted_message(%{"target" => "", "content" => _}, socket), do: socket
  def handle_send_targeted_message(%{"target" => _, "content" => ""}, socket), do: socket

  def handle_send_targeted_message(%{"target" => target, "content" => content}, socket) do
    case Ichor.Operator.send(target, content) do
      {:ok, 0} ->
        Phoenix.LiveView.push_event(socket, "toast", %{
          message: "No targets found",
          type: "warning"
        })

      {:ok, delivered} ->
        Phoenix.LiveView.push_event(socket, "toast", %{
          message: "Sent to #{delivered} agent(s)",
          type: "success"
        })
    end
  end

  defp resolve_label(sid, socket) do
    case Enum.find(socket.assigns[:sessions] || [], fn s -> s.session_id == sid end) do
      %{name: name} when is_binary(name) -> name
      _ -> String.slice(sid, 0..7)
    end
  end
end
