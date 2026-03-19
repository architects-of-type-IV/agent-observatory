defmodule IchorWeb.DashboardSessionControlHandlers do
  @moduledoc """
  LiveView event handlers for session control functionality.
  Handles pause, resume, and shutdown operations for agents.
  Pause/resume goes through HITLRelay for message buffering.
  """

  alias Ichor.EventBuffer
  alias Ichor.Fleet.{AgentProcess, FleetSupervisor, TeamSupervisor}
  alias Ichor.Gateway.AgentRegistry.AgentEntry
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Gateway.HITLRelay

  import IchorWeb.DashboardToast, only: [push_toast: 3]

  def dispatch("pause_agent", p, s), do: handle_pause_agent(p, s)
  def dispatch("resume_agent", p, s), do: handle_resume_agent(p, s)
  def dispatch("shutdown_agent", p, s), do: handle_shutdown_agent(p, s)
  def dispatch("hitl_approve", p, s), do: handle_hitl_approve(p, s)
  def dispatch("hitl_reject", p, s), do: handle_hitl_reject(p, s)
  def dispatch("kill_switch_click", p, s), do: handle_kill_switch_click(p, s)
  def dispatch("kill_switch_first_confirm", p, s), do: handle_kill_switch_first_confirm(p, s)
  def dispatch("kill_switch_second_confirm", p, s), do: handle_kill_switch_second_confirm(p, s)
  def dispatch("kill_switch_cancel", p, s), do: handle_kill_switch_cancel(p, s)
  def dispatch("push_instructions_intent", p, s), do: handle_push_instructions_intent(p, s)
  def dispatch("push_instructions_confirm", p, s), do: handle_push_instructions_confirm(p, s)
  def dispatch("push_instructions_cancel", p, s), do: handle_push_instructions_cancel(p, s)

  def handle_pause_agent(%{"session_id" => session_id}, socket) do
    HITLRelay.pause(session_id, session_id, "operator", "Operator paused from dashboard")
    Ichor.Signals.subscribe(:gate_open, session_id)
    Ichor.Signals.subscribe(:gate_close, session_id)

    Ichor.MessageRouter.send(%{
      from: "operator",
      to: session_id,
      content: "Pause requested by dashboard",
      type: :session_control,
      metadata: %{action: "pause"}
    })

    paused = MapSet.put(socket.assigns.paused_sessions, session_id)
    short = AgentEntry.short_id(session_id)

    socket
    |> Phoenix.Component.assign(:paused_sessions, paused)
    |> notify_archon_hitl(:paused, short, session_id)
    |> push_toast(:info, "Agent paused -- messages will be buffered")
  end

  @doc """
  Handle resuming an agent session.
  Unpauses via HITLRelay (flushes buffered messages) AND sends resume command.
  """
  def handle_resume_agent(%{"session_id" => session_id}, socket) do
    HITLRelay.unpause(session_id, session_id, "operator")

    Ichor.MessageRouter.send(%{
      from: "operator",
      to: session_id,
      content: "Resume requested by dashboard",
      type: :session_control,
      metadata: %{action: "resume"}
    })

    paused = MapSet.delete(socket.assigns.paused_sessions, session_id)

    socket
    |> Phoenix.Component.assign(:paused_sessions, paused)
    |> push_toast(:info, "Agent resumed -- buffered messages flushed")
  end

  @doc """
  Handle approving buffered messages (same as resume -- flush and unpause).
  """
  def handle_hitl_approve(%{"session_id" => session_id}, socket) do
    paused = MapSet.delete(socket.assigns.paused_sessions, session_id)

    case HITLRelay.unpause(session_id, session_id, "operator") do
      {:ok, :not_paused} ->
        socket
        |> Phoenix.Component.assign(:paused_sessions, paused)
        |> push_toast(:info, "Session was not paused")

      {:ok, count} ->
        socket
        |> Phoenix.Component.assign(:paused_sessions, paused)
        |> push_toast(:info, "Approved: #{count} buffered messages flushed")
    end
  end

  @doc """
  Handle rejecting buffered messages (discard buffer and unpause).
  """
  def handle_hitl_reject(%{"session_id" => session_id}, socket) do
    HITLRelay.reject(session_id, session_id, "operator")
    paused = MapSet.delete(socket.assigns.paused_sessions, session_id)

    socket
    |> Phoenix.Component.assign(:paused_sessions, paused)
    |> push_toast(:warning, "Rejected: buffered messages discarded")
  end

  @doc """
  Handle shutting down an agent session.
  Sends shutdown command, marks ended in registry, and stops the AgentProcess.
  """
  def handle_shutdown_agent(%{"session_id" => session_id}, socket) do
    Ichor.MessageRouter.send(%{
      from: "operator",
      to: session_id,
      content: "Shutdown requested by dashboard",
      type: :session_control,
      metadata: %{action: "shutdown"}
    })

    tmux_killed = kill_tmux_for_agent(session_id)

    beam_stopped =
      case AgentProcess.lookup(session_id) do
        {pid, meta} ->
          result =
            case meta[:team] do
              nil -> FleetSupervisor.terminate_agent(session_id)
              team -> TeamSupervisor.terminate_member(team, session_id)
            end

          # Fallback: if not under a supervisor, stop directly
          if result == {:error, :not_found} do
            try do
              GenServer.stop(pid, :normal)
            catch
              :exit, _ -> :ok
            end
          end

          true

        nil ->
          false
      end

    EventBuffer.tombstone_session(session_id)

    short = String.slice(session_id, 0..7)

    details = [
      if(tmux_killed, do: "tmux killed", else: "no tmux"),
      if(beam_stopped, do: "process stopped", else: "no process")
    ]

    socket
    |> Phoenix.Component.assign(:selected_command_agent, nil)
    |> push_toast(:warning, "#{short} -- #{Enum.join(details, " / ")}")
  end

  # Phase 5: Kill-switch state machine
  def handle_kill_switch_click(_params, socket) do
    Phoenix.Component.assign(socket, :kill_switch_confirm_step, :first)
  end

  def handle_kill_switch_first_confirm(_params, socket) do
    Phoenix.Component.assign(socket, :kill_switch_confirm_step, :second)
  end

  def handle_kill_switch_second_confirm(
        _params,
        %{assigns: %{kill_switch_confirm_step: :second}} = socket
      ) do
    dispatch_mesh_pause(socket)
    Phoenix.Component.assign(socket, :kill_switch_confirm_step, nil)
  end

  def handle_kill_switch_second_confirm(_params, socket) do
    Phoenix.Component.assign(socket, :kill_switch_confirm_step, nil)
  end

  def handle_kill_switch_cancel(_params, socket) do
    Phoenix.Component.assign(socket, :kill_switch_confirm_step, nil)
  end

  # Phase 5: Global Instructions handlers
  def handle_push_instructions_intent(%{"agent_class" => agent_class}, socket) do
    Phoenix.Component.assign(socket, :instructions_confirm_pending, agent_class)
  end

  def handle_push_instructions_confirm(
        %{"agent_class" => agent_class, "instructions" => instructions},
        socket
      ) do
    Ichor.Signals.emit(:agent_instructions, agent_class, %{
      agent_class: agent_class,
      instructions: instructions
    })

    socket
    |> Phoenix.Component.assign(:instructions_confirm_pending, nil)
    |> Phoenix.Component.assign(
      :instructions_banner,
      {:success, "Instructions pushed to #{agent_class}"}
    )
  end

  def handle_push_instructions_cancel(_params, socket) do
    Phoenix.Component.assign(socket, :instructions_confirm_pending, nil)
  end

  defp dispatch_mesh_pause(socket) do
    Ichor.Signals.emit(:mesh_pause, %{initiated_by: "god_mode"})

    socket
  end

  defp kill_tmux_for_agent(session_id) do
    tmux_target =
      case AgentProcess.lookup(session_id) do
        {_pid, %{channels: %{tmux: name}}} when is_binary(name) -> name
        _ -> session_id
      end

    case Tmux.run_command(["has-session", "-t", tmux_target]) do
      {:ok, _} ->
        Tmux.run_command(["kill-session", "-t", tmux_target])
        true

      _ ->
        false
    end
  end

  defp notify_archon_hitl(socket, action, agent_short, session_id) do
    content =
      case action do
        :paused ->
          "[HITL] Agent #{agent_short} (#{session_id}) has been paused. " <>
            "Messages to this agent are now being buffered. " <>
            "Review the HITL Gate in the fleet detail panel to approve or reject."
      end

    msg = %{role: :system, content: content}
    messages = (socket.assigns[:archon_messages] || []) ++ [msg]

    socket
    |> Phoenix.Component.assign(:archon_messages, messages)
    |> Phoenix.Component.assign(:show_archon, true)
  end
end
