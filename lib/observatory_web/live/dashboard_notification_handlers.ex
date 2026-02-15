defmodule ObservatoryWeb.DashboardNotificationHandlers do
  @moduledoc """
  Handlers for agent crash notifications, toasts, and browser notifications.
  """

  def handle_agent_crashed(session_id, team_name, reassigned_count, socket) do
    short_sid = String.slice(session_id, 0, 8)

    msg =
      if reassigned_count > 0 do
        "Agent #{short_sid} crashed in team #{team_name}. #{reassigned_count} task(s) reassigned."
      else
        "Agent #{short_sid} crashed in team #{team_name}."
      end

    socket |> Phoenix.LiveView.put_flash(:info, msg)
  end
end
