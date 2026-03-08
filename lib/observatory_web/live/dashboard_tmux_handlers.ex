defmodule ObservatoryWeb.DashboardTmuxHandlers do
  @moduledoc """
  LiveView event handlers for tmux session management.
  Supports multi-panel tmux: multiple sessions open simultaneously
  in tabbed or tiled layout.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Observatory.AgentSpawner
  alias Observatory.Gateway.Channels.Tmux

  def handle_connect_tmux(%{"session" => session_name}, socket) do
    panels = socket.assigns.tmux_panels

    if session_name in panels do
      # Already open -- just switch to it
      assign(socket, active_tmux_session: session_name)
    else
      output = capture_output(session_name)

      socket
      |> assign(:tmux_panels, panels ++ [session_name])
      |> assign(:tmux_outputs, Map.put(socket.assigns.tmux_outputs, session_name, output))
      |> assign(:active_tmux_session, session_name)
      |> assign(:tmux_output, output)
      |> push_event("toast", %{message: "Opened #{session_name}", type: "success"})
    end
  end

  def handle_disconnect_tmux(_params, socket) do
    active = socket.assigns.active_tmux_session
    panels = List.delete(socket.assigns.tmux_panels, active)
    outputs = Map.delete(socket.assigns.tmux_outputs, active)

    # Switch to next panel or close
    next_active = List.first(panels)

    socket
    |> assign(:tmux_panels, panels)
    |> assign(:tmux_outputs, outputs)
    |> assign(:active_tmux_session, next_active)
    |> assign(:tmux_output, Map.get(outputs, next_active, ""))
  end

  def handle_close_all_tmux(_params, socket) do
    socket
    |> assign(:tmux_panels, [])
    |> assign(:tmux_outputs, %{})
    |> assign(:active_tmux_session, nil)
    |> assign(:tmux_output, "")
  end

  def handle_switch_tmux_tab(%{"session" => session_name}, socket) do
    output = Map.get(socket.assigns.tmux_outputs, session_name, "")

    socket
    |> assign(:active_tmux_session, session_name)
    |> assign(:tmux_output, output)
  end

  def handle_toggle_tmux_layout(_params, socket) do
    new_layout = if socket.assigns.tmux_layout == :tabs, do: :tiled, else: :tabs
    assign(socket, :tmux_layout, new_layout)
  end

  def handle_send_tmux_keys(%{"keys" => keys}, socket) do
    case socket.assigns.active_tmux_session do
      nil ->
        socket

      session ->
        Tmux.run_command(["send-keys", "-t", session, keys, "Enter"])
        output = capture_output(session)

        socket
        |> assign(:tmux_output, output)
        |> assign(:tmux_outputs, Map.put(socket.assigns.tmux_outputs, session, output))
    end
  end

  def handle_kill_tmux_session(_params, socket) do
    case socket.assigns.active_tmux_session do
      nil ->
        socket

      session ->
        Tmux.run_command(["kill-session", "-t", session])

        panels = List.delete(socket.assigns.tmux_panels, session)
        outputs = Map.delete(socket.assigns.tmux_outputs, session)
        next_active = List.first(panels)

        socket
        |> assign(:tmux_panels, panels)
        |> assign(:tmux_outputs, outputs)
        |> assign(:active_tmux_session, next_active)
        |> assign(:tmux_output, Map.get(outputs, next_active, ""))
        |> push_event("toast", %{message: "Killed #{session}", type: "warning"})
    end
  end

  def handle_launch_session(%{"cwd" => cwd} = _params, socket) when cwd != "" do
    case AgentSpawner.spawn_agent(%{cwd: cwd}) do
      {:ok, result} ->
        push_event(socket, "toast", %{
          message: "Launched #{result.name} in #{Path.basename(cwd)}",
          type: "success"
        })

      {:error, reason} ->
        push_event(socket, "toast", %{
          message: "Launch failed: #{inspect(reason)}",
          type: "error"
        })
    end
  end

  def handle_launch_session(_params, socket) do
    push_event(socket, "toast", %{message: "Select a project first", type: "error"})
  end

  @doc """
  Refresh all open tmux panel outputs. Called from heartbeat handler.
  """
  def refresh_tmux_panels(socket) do
    panels = socket.assigns.tmux_panels

    if panels == [] do
      socket
    else
      outputs =
        Enum.reduce(panels, socket.assigns.tmux_outputs, fn session, acc ->
          Map.put(acc, session, capture_output(session))
        end)

      active = socket.assigns.active_tmux_session
      active_output = Map.get(outputs, active, "")

      socket
      |> assign(:tmux_outputs, outputs)
      |> assign(:tmux_output, active_output)
    end
  end

  defp capture_output(session_name) do
    case Tmux.capture_pane(session_name, lines: 80) do
      {:ok, text} -> text
      {:error, _} -> "Session ended or unavailable."
    end
  end
end
