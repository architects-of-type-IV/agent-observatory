defmodule ObservatoryWeb.DashboardSlideoutHandlers do
  @moduledoc """
  Agent slideout panel and topology node selection handlers.
  """

  import Phoenix.Component, only: [assign: 3]
  import ObservatoryWeb.DashboardFormatHelpers, only: [session_duration_sec: 1]

  def handle_open_agent_slideout(sid, socket) do
    # Unwatch previous agent if any
    if socket.assigns.agent_slideout do
      prev_sid = socket.assigns.agent_slideout[:session_id]

      if prev_sid,
        do: Phoenix.PubSub.unsubscribe(Observatory.PubSub, "agent:#{prev_sid}:activity")

      if prev_sid, do: Observatory.Gateway.AgentRegistry.unwatch(prev_sid)
    end

    agent = Observatory.Gateway.AgentRegistry.get(sid)
    Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:#{sid}:activity")
    Observatory.Gateway.AgentRegistry.watch(sid)

    activity = build_slideout_activity(sid, socket.assigns.events, socket.assigns.messages)

    socket
    |> assign(:agent_slideout, agent || %{session_id: sid})
    |> assign(:slideout_terminal, "")
    |> assign(:slideout_activity, activity)
  end

  def handle_close_agent_slideout(socket) do
    if socket.assigns.agent_slideout do
      sid = socket.assigns.agent_slideout[:session_id]

      if sid,
        do: Phoenix.PubSub.unsubscribe(Observatory.PubSub, "agent:#{sid}:activity")

      if sid, do: Observatory.Gateway.AgentRegistry.unwatch(sid)
    end

    socket
    |> assign(:agent_slideout, nil)
    |> assign(:slideout_terminal, "")
    |> assign(:slideout_activity, [])
  end

  def handle_node_selected(trace_id, socket) do
    events = socket.assigns.events
    now = socket.assigns.now

    session_events = Enum.filter(events, fn e -> e.session_id == trace_id end)

    info =
      if session_events != [] do
        sorted = Enum.sort_by(session_events, & &1.inserted_at, {:desc, DateTime})
        latest = hd(sorted)
        ended? = Enum.any?(session_events, &(&1.hook_event_type == :SessionEnd))

        model =
          Enum.find_value(session_events, fn e ->
            if e.hook_event_type == :SessionStart,
              do: (e.payload || %{})["model"] || e.model_name
          end) || Enum.find_value(session_events, & &1.model_name)

        status =
          cond do
            ended? -> :ended
            DateTime.diff(now, latest.inserted_at, :second) > 120 -> :idle
            true -> :active
          end

        first = Enum.min_by(session_events, & &1.inserted_at, DateTime)
        dur_sec = DateTime.diff(now, first.inserted_at, :second)

        %{
          session_id: trace_id,
          model: model,
          status: status,
          event_count: length(session_events),
          tool_count: Enum.count(session_events, &(&1.hook_event_type == :PreToolUse)),
          source_app: latest.source_app,
          cwd: latest.cwd || Enum.find_value(session_events, & &1.cwd),
          last_tool: latest.tool_name,
          duration: session_duration_sec(dur_sec)
        }
      else
        %{session_id: trace_id, status: :unknown, event_count: 0}
      end

    assign(socket, :selected_topology_node, info)
  end

  defp build_slideout_activity(session_id, events, messages) do
    event_items =
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

    message_items =
      messages
      |> Enum.filter(fn m ->
        m[:session_id] == session_id || m[:to] == session_id || m[:from] == session_id
      end)
      |> Enum.map(fn m ->
        %{
          type: :message,
          timestamp: m[:timestamp] || m[:inserted_at],
          content: m[:content] || m[:message] || "",
          id: "msg-#{m[:id] || :erlang.unique_integer([:positive])}"
        }
      end)

    (event_items ++ message_items)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(100)
  end
end
