defmodule IchorWeb.DashboardSlideoutHandlers do
  @moduledoc """
  Agent slideout panel and topology node selection handlers.
  """

  import Phoenix.Component, only: [assign: 3]
  import IchorWeb.DashboardFormatHelpers, only: [session_duration_sec: 1]

  alias Ichor.Fleet.AgentProcess
  alias Ichor.Gateway.OutputCapture

  def handle_open_agent_slideout(sid, socket) do
    # Unwatch previous agent if any
    if socket.assigns.agent_slideout do
      prev_sid = socket.assigns.agent_slideout[:session_id]

      if prev_sid,
        do: Phoenix.PubSub.unsubscribe(Ichor.PubSub, "agent:#{prev_sid}:activity")

      if prev_sid, do: OutputCapture.unwatch(prev_sid)
    end

    agent =
      case AgentProcess.lookup(sid) do
        {_pid, meta} -> meta
        nil -> nil
      end

    Phoenix.PubSub.subscribe(Ichor.PubSub, "agent:#{sid}:activity")
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

      if sid,
        do: Phoenix.PubSub.unsubscribe(Ichor.PubSub, "agent:#{sid}:activity")

      if sid, do: OutputCapture.unwatch(sid)
    end

    socket
    |> assign(:agent_slideout, nil)
    |> assign(:slideout_terminal, "")
    |> assign(:slideout_activity, [])
  end

  def handle_node_selected(trace_id, socket) do
    session_events = Enum.filter(socket.assigns.events, fn e -> e.session_id == trace_id end)
    info = build_node_info(trace_id, session_events, socket.assigns.now)
    assign(socket, :selected_topology_node, info)
  end

  defp build_node_info(trace_id, [], _now) do
    %{session_id: trace_id, status: :unknown, event_count: 0}
  end

  defp build_node_info(trace_id, session_events, now) do
    sorted = Enum.sort_by(session_events, & &1.inserted_at, {:desc, DateTime})
    latest = hd(sorted)
    ended? = Enum.any?(session_events, &(&1.hook_event_type == :SessionEnd))
    model = extract_model(session_events)
    status = derive_status(ended?, now, latest.inserted_at)
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
  end

  defp extract_model(session_events) do
    Enum.find_value(session_events, fn e ->
      if e.hook_event_type == :SessionStart,
        do: (e.payload || %{})["model"] || e.model_name
    end) || Enum.find_value(session_events, & &1.model_name)
  end

  defp derive_status(true, _now, _inserted_at), do: :ended

  defp derive_status(false, now, inserted_at) do
    if DateTime.diff(now, inserted_at, :second) > 120, do: :idle, else: :active
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
