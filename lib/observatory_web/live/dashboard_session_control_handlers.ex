defmodule ObservatoryWeb.DashboardSessionControlHandlers do
  @moduledoc """
  LiveView event handlers for session control functionality.
  Handles pause, resume, and shutdown operations for agents.
  """

  @doc """
  Handle pausing an agent session.
  Writes pause command to CommandQueue and sends via Mailbox.
  """
  def handle_pause_agent(%{"session_id" => session_id}, socket) do
    command = %{
      "type" => "session_control",
      "action" => "pause",
      "from" => "dashboard",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Write to CommandQueue
    Observatory.CommandQueue.write_command(session_id, command)

    # Send via Mailbox
    Observatory.Mailbox.send_message(
      session_id,
      "dashboard",
      "Pause requested by dashboard",
      type: :session_control,
      metadata: %{action: "pause"}
    )

    socket
    |> Phoenix.LiveView.put_flash(:info, "Pause command sent to agent #{String.slice(session_id, 0..7)}")
  end

  @doc """
  Handle resuming an agent session.
  Writes resume command to CommandQueue and sends via Mailbox.
  """
  def handle_resume_agent(%{"session_id" => session_id}, socket) do
    command = %{
      "type" => "session_control",
      "action" => "resume",
      "from" => "dashboard",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Write to CommandQueue
    Observatory.CommandQueue.write_command(session_id, command)

    # Send via Mailbox
    Observatory.Mailbox.send_message(
      session_id,
      "dashboard",
      "Resume requested by dashboard",
      type: :session_control,
      metadata: %{action: "resume"}
    )

    socket
    |> Phoenix.LiveView.put_flash(:info, "Resume command sent to agent #{String.slice(session_id, 0..7)}")
  end

  @doc """
  Handle shutting down an agent session.
  Writes shutdown command to CommandQueue and sends via Mailbox.
  """
  def handle_shutdown_agent(%{"session_id" => session_id}, socket) do
    command = %{
      "type" => "session_control",
      "action" => "shutdown",
      "from" => "dashboard",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Write to CommandQueue
    Observatory.CommandQueue.write_command(session_id, command)

    # Send via Mailbox
    Observatory.Mailbox.send_message(
      session_id,
      "dashboard",
      "Shutdown requested by dashboard",
      type: :session_control,
      metadata: %{action: "shutdown"}
    )

    socket
    |> Phoenix.LiveView.put_flash(:warning, "Shutdown command sent to agent #{String.slice(session_id, 0..7)}")
  end
end
