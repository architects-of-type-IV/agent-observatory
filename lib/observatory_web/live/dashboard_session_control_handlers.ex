defmodule ObservatoryWeb.DashboardSessionControlHandlers do
  @moduledoc """
  LiveView event handlers for session control functionality.
  Handles pause, resume, and shutdown operations for agents.
  Pause/resume goes through HITLRelay for message buffering.
  """

  alias Observatory.Gateway.HITLRelay

  @doc """
  Handle pausing an agent session.
  Pauses via HITLRelay (buffers messages) AND sends pause command to agent.
  """
  def handle_pause_agent(%{"session_id" => session_id}, socket) do
    # Pause via HITLRelay for message buffering
    HITLRelay.pause(session_id, session_id, "operator", "Operator paused from dashboard")

    # Subscribe to HITL events for this session
    Phoenix.PubSub.subscribe(Observatory.PubSub, "session:hitl:#{session_id}")

    # Also send pause command to agent via CommandQueue + Mailbox
    command = %{
      "type" => "session_control",
      "action" => "pause",
      "from" => "operator",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Observatory.CommandQueue.write_command(session_id, command)

    Observatory.Mailbox.send_message(
      session_id,
      "operator",
      "Pause requested by dashboard",
      type: :session_control,
      metadata: %{action: "pause"}
    )

    socket
    |> Phoenix.LiveView.put_flash(
      :info,
      "Agent paused -- messages will be buffered"
    )
  end

  @doc """
  Handle resuming an agent session.
  Unpauses via HITLRelay (flushes buffered messages) AND sends resume command.
  """
  def handle_resume_agent(%{"session_id" => session_id}, socket) do
    # Unpause via HITLRelay -- flushes buffered messages
    HITLRelay.unpause(session_id, session_id, "operator")

    command = %{
      "type" => "session_control",
      "action" => "resume",
      "from" => "operator",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Observatory.CommandQueue.write_command(session_id, command)

    Observatory.Mailbox.send_message(
      session_id,
      "operator",
      "Resume requested by dashboard",
      type: :session_control,
      metadata: %{action: "resume"}
    )

    socket
    |> Phoenix.LiveView.put_flash(
      :info,
      "Agent resumed -- buffered messages flushed"
    )
  end

  @doc """
  Handle approving buffered messages (same as resume -- flush and unpause).
  """
  def handle_hitl_approve(%{"session_id" => session_id}, socket) do
    case HITLRelay.unpause(session_id, session_id, "operator") do
      {:ok, :not_paused} ->
        Phoenix.LiveView.put_flash(socket, :info, "Session was not paused")

      {:ok, count} ->
        Phoenix.LiveView.put_flash(socket, :info, "Approved: #{count} buffered messages flushed")
    end
  end

  @doc """
  Handle rejecting buffered messages (discard buffer and unpause).
  """
  def handle_hitl_reject(%{"session_id" => session_id}, socket) do
    HITLRelay.reject(session_id, session_id, "operator")

    socket
    |> Phoenix.LiveView.put_flash(:warning, "Rejected: buffered messages discarded")
  end

  @doc """
  Handle shutting down an agent session.
  Writes shutdown command to CommandQueue and sends via Mailbox.
  """
  def handle_shutdown_agent(%{"session_id" => session_id}, socket) do
    command = %{
      "type" => "session_control",
      "action" => "shutdown",
      "from" => "operator",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Observatory.CommandQueue.write_command(session_id, command)

    Observatory.Mailbox.send_message(
      session_id,
      "operator",
      "Shutdown requested by dashboard",
      type: :session_control,
      metadata: %{action: "shutdown"}
    )

    socket
    |> Phoenix.LiveView.put_flash(
      :warning,
      "Shutdown command sent to agent #{String.slice(session_id, 0..7)}"
    )
  end

  # Phase 5: Kill-switch state machine
  def handle_kill_switch_click(_params, socket) do
    Phoenix.Component.assign(socket, :kill_switch_confirm_step, :first)
  end

  def handle_kill_switch_first_confirm(_params, socket) do
    Phoenix.Component.assign(socket, :kill_switch_confirm_step, :second)
  end

  def handle_kill_switch_second_confirm(_params, %{assigns: %{kill_switch_confirm_step: :second}} = socket) do
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

  def handle_push_instructions_confirm(%{"agent_class" => agent_class, "instructions" => instructions}, socket) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "agent:#{agent_class}:instructions",
      {:global_instructions, %{agent_class: agent_class, instructions: instructions}}
    )

    socket
    |> Phoenix.Component.assign(:instructions_confirm_pending, nil)
    |> Phoenix.Component.assign(:instructions_banner, {:success, "Instructions pushed to #{agent_class}"})
  end

  def handle_push_instructions_cancel(_params, socket) do
    Phoenix.Component.assign(socket, :instructions_confirm_pending, nil)
  end

  defp dispatch_mesh_pause(socket) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "gateway:mesh_control",
      {:mesh_pause, %{initiated_by: "god_mode", timestamp: DateTime.utc_now()}}
    )
    socket
  end
end
