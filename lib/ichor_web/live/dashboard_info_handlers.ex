defmodule IchorWeb.DashboardInfoHandlers do
  @moduledoc """
  Signal and process message handlers for the dashboard LiveView.
  Debounces recompute to coalesce rapid-fire events within a 100ms window.
  Each dispatch/2 clause returns {:noreply, socket}.
  """

  import Phoenix.Component, only: [assign: 3]
  import IchorWeb.DashboardState, only: [recompute: 1]
  import IchorWeb.DashboardTmuxHandlers, only: [refresh_tmux_panels: 1]
  import IchorWeb.DashboardMessagingHandlers, only: [handle_new_mailbox_message: 2]
  import IchorWeb.DashboardNotificationHandlers, only: [handle_agent_crashed: 4]

  alias Ichor.Factory.Project
  alias Ichor.Infrastructure.Tmux
  alias Ichor.Events.Event
  alias IchorWeb.{DashboardArchonHandlers, DashboardMesHandlers}

  @max_events 500
  @recompute_debounce_ms 100

  defp schedule_recompute(%{assigns: %{recompute_timer: timer}} = socket) when not is_nil(timer),
    do: socket

  defp schedule_recompute(socket) do
    timer = Process.send_after(self(), :do_recompute, @recompute_debounce_ms)
    assign(socket, :recompute_timer, timer)
  end

  def dispatch(:do_recompute, socket) do
    {:noreply, socket |> assign(:recompute_timer, nil) |> recompute()}
  end

  def dispatch(%Event{topic: "events.hook.ingested", data: %{event: event}}, socket) do
    events = [event | socket.assigns.events] |> Enum.take(@max_events)

    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:now, DateTime.utc_now())
     |> maybe_refresh_archon_manager()
     |> schedule_recompute()}
  end

  def dispatch(%Event{topic: "team.tasks.updated"}, socket),
    do: {:noreply, schedule_recompute(socket)}

  def dispatch(%Event{topic: "agent.crashed", data: data}, socket),
    do:
      {:noreply,
       handle_agent_crashed(data.session_id, data[:team_name], 0, socket) |> schedule_recompute()}

  def dispatch(%Event{topic: "fleet.agent.started"}, socket),
    do: {:noreply, schedule_recompute(socket)}

  def dispatch(%Event{topic: "fleet.agent.stopped"}, socket),
    do: {:noreply, schedule_recompute(socket)}

  def dispatch(%Event{topic: "fleet.registry.changed"}, socket),
    do: {:noreply, schedule_recompute(socket)}

  def dispatch({:refresh_terminal, session}, socket) do
    case Tmux.capture_pane(session, ansi: true) do
      {:ok, output} ->
        {:noreply,
         socket
         |> assign(:tmux_outputs, Map.put(socket.assigns.tmux_outputs, session, output))
         |> Phoenix.LiveView.push_event("terminal_output", %{session: session, data: output})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def dispatch(%Event{topic: "system.heartbeat"}, %{assigns: %{tmux_panels: [_ | _]}} = socket),
    do: {:noreply, refresh_tmux_panels(socket)}

  def dispatch(%Event{topic: "system.heartbeat"}, socket), do: {:noreply, socket}

  def dispatch(
        %Event{topic: "messages.delivered", data: %{msg_map: %{message: message}}},
        socket
      ),
      do: handle_new_mailbox_message(message, socket)

  def dispatch(%Event{topic: "pipeline.status", data: %{state_map: state}}, socket) do
    merged = Map.merge(socket.assigns.pipeline_state, state)
    {:noreply, socket |> assign(:pipeline_state, merged) |> maybe_refresh_archon_manager()}
  end

  def dispatch(
        %Event{topic: "agent.terminal.output", data: %{session_id: sid, output: output}},
        socket
      ) do
    case socket.assigns.agent_slideout do
      %{session_id: ^sid} -> {:noreply, assign(socket, :slideout_terminal, output)}
      _ -> {:noreply, socket}
    end
  end

  # Nudge/gate: notifications only -- no data changed, no recompute
  @nudge_topics ~w(agent.nudge.warning agent.nudge.sent agent.nudge.escalated agent.nudge.zombie)

  def dispatch(%Event{topic: topic}, socket) when topic in @nudge_topics,
    do: {:noreply, maybe_refresh_archon_manager(socket)}

  def dispatch(%Event{topic: "gateway.gate.passed"}, socket),
    do: {:noreply, maybe_refresh_archon_manager(socket)}

  def dispatch(%Event{topic: "gateway.gate.failed"}, socket),
    do: {:noreply, maybe_refresh_archon_manager(socket)}

  @gateway_topics ~w(gateway.entropy.alert gateway.node.state_update)

  def dispatch(%Event{topic: topic}, socket) when topic in @gateway_topics,
    do: {:noreply, maybe_refresh_archon_manager(socket)}

  # ADR-026: signal pipeline activations
  def dispatch({:signal_activated, %Ichor.Signals.Signal{} = signal}, socket) do
    {:noreply, socket |> push_signal_toast(signal) |> schedule_recompute()}
  end

  def dispatch({:archon_response, result}, socket),
    do: {:noreply, DashboardArchonHandlers.handle_archon_response(result, socket)}

  def dispatch({:dismiss_toast, id}, socket),
    do: {:noreply, IchorWeb.DashboardToast.dismiss_toast(socket, id)}

  def dispatch(%Event{topic: "mes.project.created"}, socket) do
    {:noreply, assign(socket, :mes_projects, Project.list_all!())}
  end

  @mes_scheduler_topics ~w(mes.scheduler.paused mes.scheduler.resumed mes.cycle.started)

  def dispatch(%Event{topic: topic}, socket) when topic in @mes_scheduler_topics,
    do:
      {:noreply,
       assign(socket, :mes_scheduler_status, DashboardMesHandlers.fetch_scheduler_status())}

  def dispatch(%Event{topic: "mes.plugin.loaded"}, socket) do
    {:noreply, assign(socket, :mes_projects, Project.list_all!())}
  end

  @mes_archon_topics ~w(mes.cycle.failed mes.cycle.timeout mes.project.picked_up mes.research.ingested mes.research.ingest_failed)

  def dispatch(%Event{topic: topic}, socket) when topic in @mes_archon_topics,
    do: {:noreply, maybe_refresh_archon_manager(socket)}

  @planning_reload_topics ~w(planning.artifact.created planning.team.ready planning.run.complete planning.team.killed)

  def dispatch(%Event{topic: topic}, socket) when topic in @planning_reload_topics do
    {:noreply, reload_planning_project(socket)}
  end

  # Catch-all: ignore unknown events (new events added won't crash)
  def dispatch(%Event{}, socket), do: {:noreply, maybe_refresh_archon_manager(socket)}

  defp reload_planning_project(%{assigns: %{selected_mes_project: nil}} = socket), do: socket

  defp reload_planning_project(socket) do
    project =
      case Project.get(socket.assigns.selected_mes_project.id) do
        {:ok, loaded_project} -> loaded_project
        _ -> nil
      end

    assign(socket, :planning_project, project)
  end

  defp maybe_refresh_archon_manager(socket), do: socket

  defp push_signal_toast(socket, signal) do
    {level, msg} = signal_toast(signal)
    IchorWeb.DashboardToast.push_toast(socket, level, msg)
  end

  defp signal_toast(%Ichor.Signals.Signal{name: "agent.tool.budget"} = s) do
    count = s.metadata[:count]
    limit = s.metadata[:limit]
    key = String.slice(to_string(s.key), 0, 12)
    {:warning, "Budget exhausted — session #{key} (#{count}/#{limit} tools)"}
  end

  defp signal_toast(%Ichor.Signals.Signal{name: "agent.message.protocol"} = s) do
    violations = s.metadata[:violations] || []
    {:error, "Protocol violation — #{s.key}: #{length(violations)} comm rule violation(s)"}
  end

  defp signal_toast(%Ichor.Signals.Signal{name: "agent.entropy"} = s) do
    score = s.metadata[:entropy_score]
    key = String.slice(to_string(s.key), 0, 12)
    {:warning, "Loop detected — session #{key} entropy #{score}"}
  end

  defp signal_toast(%Ichor.Signals.Signal{name: name} = s) do
    {:info, "Signal #{name} — key=#{s.key} events=#{length(s.events)}"}
  end
end
