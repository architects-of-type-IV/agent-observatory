defmodule IchorWeb.DashboardViewRouterTest do
  use ExUnit.Case, async: true

  alias IchorWeb.DashboardViewRouter

  test "assign_view maps legacy aliases to current visible views" do
    socket = socket()

    socket = DashboardViewRouter.assign_view(socket, "tasks")

    assert socket.assigns.view_mode == :pipeline

    socket = DashboardViewRouter.assign_view(socket, "messages")

    assert socket.assigns.view_mode == :command
    assert socket.assigns.activity_tab == :comms
  end

  test "assign_view falls back to command for unknown modes" do
    socket = socket()

    socket = DashboardViewRouter.assign_view(socket, "definitely_unknown")

    assert socket.assigns.view_mode == :command
  end

  test "resolve preserves atoms" do
    assert DashboardViewRouter.resolve(:agent_focus) == {:agent_focus, []}
  end

  defp socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
  end
end
