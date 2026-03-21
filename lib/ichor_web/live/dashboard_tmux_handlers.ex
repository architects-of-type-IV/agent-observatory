defmodule IchorWeb.DashboardTmuxHandlers do
  @moduledoc """
  LiveView event handlers for tmux session management.
  Supports multi-panel tmux: multiple sessions open simultaneously
  in tabbed or tiled layout.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  import IchorWeb.DashboardToast, only: [push_toast: 3]

  alias Ichor.Infrastructure.AgentLaunch
  alias Ichor.Infrastructure.Tmux

  def dispatch("connect_tmux", p, s), do: handle_connect_tmux(p, s)
  def dispatch("disconnect_tmux", p, s), do: handle_disconnect_tmux(p, s)
  def dispatch("disconnect_tmux_tab", p, s), do: handle_disconnect_tmux_tab(p, s)
  def dispatch("close_all_tmux", p, s), do: handle_close_all_tmux(p, s)
  def dispatch("switch_tmux_tab", p, s), do: handle_switch_tmux_tab(p, s)
  def dispatch("toggle_tmux_layout", p, s), do: handle_toggle_tmux_layout(p, s)
  def dispatch("send_tmux_keys", p, s), do: handle_send_tmux_keys(p, s)
  def dispatch("kill_tmux_session", p, s), do: handle_kill_tmux_session(p, s)
  def dispatch("kill_sidebar_tmux", p, s), do: handle_kill_sidebar_tmux(p, s)
  def dispatch("launch_session", p, s), do: handle_launch_session(p, s)
  # Terminal panel events
  def dispatch("toggle_terminal_panel", p, s), do: handle_toggle_terminal_panel(p, s)
  def dispatch("close_terminal_panel", p, s), do: handle_close_terminal_panel(p, s)
  def dispatch("cycle_panel_position", p, s), do: handle_cycle_panel_position(p, s)
  def dispatch("cycle_panel_size", p, s), do: handle_cycle_panel_size(p, s)
  def dispatch("set_panel_position", p, s), do: handle_set_panel_position(p, s)
  def dispatch("set_panel_size", p, s), do: handle_set_panel_size(p, s)
  def dispatch("set_panel_split", p, s), do: handle_set_panel_split(p, s)
  def dispatch("set_panel_theme", p, s), do: handle_set_panel_theme(p, s)
  def dispatch("terminal_panel_init", p, s), do: handle_terminal_panel_init(p, s)
  def dispatch("terminal_panel_resize", p, s), do: handle_terminal_panel_resize(p, s)
  def dispatch("toggle_session_picker", p, s), do: handle_toggle_session_picker(p, s)
  def dispatch("toggle_panel_settings", p, s), do: handle_toggle_panel_settings(p, s)

  def handle_connect_tmux(%{"session" => session_name}, socket) do
    panels = socket.assigns.tmux_panels

    if session_name in panels do
      # Already open -- just switch to it and replay output
      output = Map.get(socket.assigns.tmux_outputs, session_name, "")

      socket
      |> assign(active_tmux_session: session_name)
      |> assign(:panel_visible, true)
      |> assign(:show_session_picker, false)
      |> push_event("terminal_output", %{session: session_name, data: output})
    else
      output = capture_output(session_name)

      socket
      |> assign(:tmux_panels, panels ++ [session_name])
      |> assign(:tmux_outputs, Map.put(socket.assigns.tmux_outputs, session_name, output))
      |> assign(:active_tmux_session, session_name)
      |> assign(:panel_visible, true)
      |> assign(:show_session_picker, false)
      |> push_event("terminal_output", %{session: session_name, data: output})
      |> push_event("toast", %{message: "Opened #{session_name}", type: "success"})
    end
  end

  def handle_disconnect_tmux(_params, socket) do
    active = socket.assigns.active_tmux_session
    panels = List.delete(socket.assigns.tmux_panels, active)
    outputs = Map.delete(socket.assigns.tmux_outputs, active)

    # Switch to next panel or close
    next_active = List.first(panels)

    socket =
      socket
      |> assign(:tmux_panels, panels)
      |> assign(:tmux_outputs, outputs)
      |> assign(:active_tmux_session, next_active)

    case next_active do
      nil ->
        socket

      session ->
        push_event(socket, "terminal_output", %{
          session: session,
          data: Map.get(outputs, session, "")
        })
    end
  end

  def handle_close_all_tmux(_params, socket) do
    socket
    |> assign(:tmux_panels, [])
    |> assign(:tmux_outputs, %{})
    |> assign(:active_tmux_session, nil)
  end

  def handle_switch_tmux_tab(%{"session" => session_name}, socket) do
    output = Map.get(socket.assigns.tmux_outputs, session_name, "")

    socket
    |> assign(:active_tmux_session, session_name)
    |> push_event("terminal_output", %{session: session_name, data: output})
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
        |> assign(:tmux_outputs, Map.put(socket.assigns.tmux_outputs, session, output))
        |> push_event("terminal_output", %{session: session, data: output})
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

        socket =
          socket
          |> assign(:tmux_panels, panels)
          |> assign(:tmux_outputs, outputs)
          |> assign(:active_tmux_session, next_active)
          |> push_event("toast", %{message: "Killed #{session}", type: "warning"})

        case next_active do
          nil -> socket
          s -> push_event(socket, "terminal_output", %{session: s, data: Map.get(outputs, s, "")})
        end
    end
  end

  def handle_kill_sidebar_tmux(%{"session" => session_name}, socket) do
    case Tmux.run_command(["has-session", "-t", session_name]) do
      {:ok, _} ->
        Tmux.run_command(["kill-session", "-t", session_name])

        # Also remove from open panels if connected
        panels = List.delete(socket.assigns.tmux_panels, session_name)
        outputs = Map.delete(socket.assigns.tmux_outputs, session_name)

        active =
          if socket.assigns.active_tmux_session == session_name,
            do: List.first(panels),
            else: socket.assigns.active_tmux_session

        socket
        |> assign(:tmux_panels, panels)
        |> assign(:tmux_outputs, outputs)
        |> assign(:active_tmux_session, active)
        |> assign(:tmux_sessions, List.delete(socket.assigns.tmux_sessions, session_name))
        |> push_toast(:warning, "Killed tmux: #{session_name}")

      _ ->
        # Session already gone -- process death already cleaned up Ichor.Registry
        socket
        |> assign(:tmux_sessions, List.delete(socket.assigns.tmux_sessions, session_name))
        |> push_toast(:info, "#{session_name} already gone")
    end
  end

  def handle_launch_session(%{"cwd" => cwd} = _params, socket) when cwd != "" do
    case AgentLaunch.spawn(%{cwd: cwd}) do
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

      # Push output for all panels so tiled mode stays fresh; tabs mode only shows active
      socket = assign(socket, :tmux_outputs, outputs)

      Enum.reduce(panels, socket, fn session, acc ->
        push_event(acc, "terminal_output", %{
          session: session,
          data: Map.get(outputs, session, "")
        })
      end)
    end
  end

  # ── Terminal panel handlers ──

  def handle_disconnect_tmux_tab(%{"session" => session_name}, socket) do
    panels = List.delete(socket.assigns.tmux_panels, session_name)
    outputs = Map.delete(socket.assigns.tmux_outputs, session_name)

    next_active =
      if socket.assigns.active_tmux_session == session_name,
        do: List.first(panels),
        else: socket.assigns.active_tmux_session

    socket =
      socket
      |> assign(:tmux_panels, panels)
      |> assign(:tmux_outputs, outputs)
      |> assign(:active_tmux_session, next_active)

    case next_active do
      nil -> socket
      s -> push_event(socket, "terminal_output", %{session: s, data: Map.get(outputs, s, "")})
    end
  end

  def handle_toggle_terminal_panel(_params, socket) do
    new_visible = !socket.assigns.panel_visible
    socket = assign(socket, :panel_visible, new_visible)

    # If showing and no panels open, auto-open first available session
    if new_visible && socket.assigns.tmux_panels == [] do
      case socket.assigns.tmux_sessions do
        [first | _] -> handle_connect_tmux(%{"session" => first}, socket)
        [] -> socket
      end
    else
      socket
    end
  end

  def handle_close_terminal_panel(_params, socket) do
    socket
    |> assign(:panel_visible, false)
    |> assign(:tmux_panels, [])
    |> assign(:tmux_outputs, %{})
    |> assign(:active_tmux_session, nil)
  end

  @position_cycle [:bottom, :right, :top, :left, :floating]

  def handle_cycle_panel_position(_params, socket) do
    current = socket.assigns.panel_position
    idx = Enum.find_index(@position_cycle, &(&1 == current)) || 0
    next = Enum.at(@position_cycle, rem(idx + 1, length(@position_cycle)))

    socket
    |> assign(:panel_position, next)
    |> push_event("terminal_panel_update", %{position: to_string(next)})
  end

  @size_cycle [25, 33, 50, 75, 100]

  def handle_cycle_panel_size(_params, socket) do
    current = socket.assigns.panel_size
    idx = Enum.find_index(@size_cycle, &(&1 == current)) || 0
    next = Enum.at(@size_cycle, rem(idx + 1, length(@size_cycle)))

    socket
    |> assign(:panel_size, next)
    |> push_event("terminal_panel_update", %{size: next})
  end

  def handle_terminal_panel_init(params, socket) do
    position = parse_position(params["position"])
    size = parse_size(params["size"])
    visible = params["visible"] == true || params["visible"] == "true"
    split = parse_split(params["split"])
    theme = parse_theme(params["theme"])

    assign(socket,
      panel_position: position,
      panel_size: size,
      panel_visible: visible,
      panel_split: split,
      panel_theme: theme
    )
  end

  def handle_terminal_panel_resize(%{"size" => size}, socket) do
    assign(socket, :panel_size, parse_size(size))
  end

  def handle_set_panel_position(%{"position" => pos}, socket) do
    position = parse_position(pos)

    socket
    |> assign(:panel_position, position)
    |> push_event("terminal_panel_update", %{position: to_string(position)})
  end

  def handle_set_panel_size(%{"size" => size}, socket) do
    parsed = parse_size(size)

    socket
    |> assign(:panel_size, parsed)
    |> push_event("terminal_panel_update", %{size: parsed})
  end

  def handle_set_panel_split(%{"split" => split_str}, socket) do
    split = parse_split(split_str)

    socket
    |> assign(:panel_split, split)
    |> push_event("terminal_panel_update", %{split: to_string(split)})
  end

  def handle_set_panel_theme(%{"theme" => theme_str}, socket) do
    theme = parse_theme(theme_str)

    socket
    |> assign(:panel_theme, theme)
    |> push_event("terminal_apply_theme", %{theme: to_string(theme)})
    |> push_event("terminal_panel_update", %{theme: to_string(theme)})
  end

  def handle_toggle_session_picker(_params, socket) do
    assign(socket, :show_session_picker, !socket.assigns[:show_session_picker])
  end

  def handle_toggle_panel_settings(_params, socket) do
    assign(socket, :show_panel_settings, !socket.assigns[:show_panel_settings])
  end

  defp parse_position("top"), do: :top
  defp parse_position("left"), do: :left
  defp parse_position("right"), do: :right
  defp parse_position("floating"), do: :floating
  defp parse_position(_), do: :bottom

  defp parse_size(size) when is_integer(size), do: max(15, min(100, size))
  defp parse_size(size) when is_binary(size), do: parse_size(String.to_integer(size))
  defp parse_size(_), do: 50

  defp parse_split("horizontal"), do: :horizontal
  defp parse_split("vertical"), do: :vertical
  defp parse_split(_), do: :none

  defp parse_theme("midnight"), do: :midnight
  defp parse_theme("aurora"), do: :aurora
  defp parse_theme("phosphor"), do: :phosphor
  defp parse_theme("solarized"), do: :solarized
  defp parse_theme("rose"), do: :rose
  defp parse_theme(_), do: :ichor

  defp capture_output(session_name) do
    case Tmux.capture_pane(session_name, lines: 80) do
      {:ok, text} -> text
      {:error, _} -> "Session ended or unavailable."
    end
  end
end
