defmodule ObservatoryWeb.DashboardTmuxHandlers do
  @moduledoc """
  LiveView event handlers for tmux session management.
  Handles connect, disconnect, send keys, kill, and launch operations.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Observatory.Gateway.Channels.Tmux

  @observatory_socket Path.expand("~/.observatory/tmux/obs.sock")

  def handle_connect_tmux(%{"session" => session_name}, socket) do
    output =
      case Tmux.capture_pane(session_name, lines: 80) do
        {:ok, text} -> text
        {:error, _} -> "Failed to capture pane output."
      end

    socket
    |> assign(active_tmux_session: session_name, tmux_output: output)
    |> push_event("toast", %{message: "Connected to #{session_name}", type: "success"})
  end

  def handle_disconnect_tmux(_params, socket) do
    assign(socket, active_tmux_session: nil, tmux_output: "")
  end

  def handle_send_tmux_keys(%{"keys" => keys}, socket) do
    case socket.assigns.active_tmux_session do
      nil ->
        socket

      session ->
        args = Tmux.socket_args() ++ ["send-keys", "-t", session, keys, "Enter"]
        System.cmd("tmux", args, stderr_to_stdout: true)

        output =
          case Tmux.capture_pane(session, lines: 80) do
            {:ok, text} -> text
            {:error, _} -> socket.assigns.tmux_output
          end

        assign(socket, :tmux_output, output)
    end
  end

  def handle_kill_tmux_session(_params, socket) do
    case socket.assigns.active_tmux_session do
      nil ->
        socket

      session ->
        args = Tmux.socket_args() ++ ["kill-session", "-t", session]
        System.cmd("tmux", args, stderr_to_stdout: true)

        socket
        |> assign(active_tmux_session: nil, tmux_output: "")
        |> push_event("toast", %{message: "Killed #{session}", type: "warning"})
    end
  end

  def handle_launch_session(%{"cwd" => cwd} = params, socket) when cwd != "" do
    session_name = "obs-#{:os.system_time(:second)}"
    command = params["command"] || "claude"

    File.mkdir_p!(Path.dirname(@observatory_socket))
    socket_args = Tmux.socket_args()

    case System.cmd("tmux", socket_args ++ [
           "new-session", "-d", "-s", session_name, "-c", cwd,
           "env", "-u", "CLAUDECODE", command
         ], stderr_to_stdout: true) do
      {_output, 0} ->
        push_event(socket, "toast", %{
          message: "Launched #{session_name} in #{Path.basename(cwd)}",
          type: "success"
        })

      {error, _code} ->
        push_event(socket, "toast", %{
          message: "Launch failed: #{String.slice(error, 0, 80)}",
          type: "error"
        })
    end
  end

  def handle_launch_session(_params, socket) do
    push_event(socket, "toast", %{message: "Select a project first", type: "error"})
  end
end
