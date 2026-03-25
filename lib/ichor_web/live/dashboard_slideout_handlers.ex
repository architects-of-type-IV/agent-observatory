defmodule IchorWeb.DashboardSlideoutHandlers do
  @moduledoc """
  Agent slideout panel handlers.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ichor.Fleet.AgentProcess
  alias Ichor.Infrastructure.OutputCapture

  def handle_open_agent_slideout(sid, socket) do
    # Unwatch previous agent if any
    if socket.assigns.agent_slideout do
      prev_sid = socket.assigns.agent_slideout[:session_id]
      if prev_sid, do: OutputCapture.unwatch(prev_sid)
    end

    agent =
      case AgentProcess.lookup(sid) do
        {_pid, meta} -> meta
        nil -> nil
      end

    OutputCapture.watch(sid)

    activity = build_slideout_activity(sid, socket.assigns.events, socket.assigns.messages)

    socket
    |> assign(:agent_slideout, agent || %{session_id: sid})
    |> assign(:slideout_terminal, "")
    |> assign(:slideout_activity, activity)
  end

  def handle_close_agent_slideout(socket) do
    if socket.assigns.agent_slideout do
      sid = socket.assigns.agent_slideout[:session_id]
      if sid, do: OutputCapture.unwatch(sid)
    end

    socket
    |> assign(:agent_slideout, nil)
    |> assign(:slideout_terminal, "")
    |> assign(:slideout_activity, [])
  end

  defp build_slideout_activity(session_id, events, messages) do
    event_items = build_event_items(session_id, events)
    message_items = build_message_items(session_id, messages)

    (event_items ++ message_items)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(100)
  end

  defp build_event_items(session_id, events) do
    events
    |> Enum.filter(fn e -> e.session_id == session_id end)
    |> Enum.map(fn e ->
      %{
        type: :event,
        timestamp: e.inserted_at,
        content: "#{e.hook_event_type}#{if e.tool_name, do: " - #{e.tool_name}", else: ""}",
        id: "ev-#{e.id}"
      }
    end)
  end

  defp build_message_items(session_id, messages) do
    messages
    |> Enum.filter(&message_matches_session?(&1, session_id))
    |> Enum.map(fn m ->
      %{
        type: :message,
        timestamp: Map.get(m, :timestamp) || Map.get(m, :inserted_at),
        content: Map.get(m, :content) || Map.get(m, :message) || "",
        id: "msg-#{Map.get(m, :id) || :erlang.unique_integer([:positive])}"
      }
    end)
  end

  defp message_matches_session?(m, session_id) do
    Map.get(m, :session_id) == session_id ||
      Map.get(m, :to) == session_id ||
      Map.get(m, :from) == session_id ||
      Map.get(m, :sender_session) == session_id ||
      Map.get(m, :recipient) == session_id
  end
end
