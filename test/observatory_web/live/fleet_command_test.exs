defmodule ObservatoryWeb.FleetCommandTest do
  use ObservatoryWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "Fleet Command view" do
    test "renders all six panels on fleet_command view", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "fleet-command-view"
      assert html =~ "mesh-topology-canvas"
      assert html =~ "throughput-panel"
      assert html =~ "cost-heatmap-panel"
      assert html =~ "infrastructure-health-panel"
      assert html =~ "latency-panel"
      assert html =~ "mtls-status-panel"
    end

    test "renders loading states when no data", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Loading..."
    end

    test "agent grid toggles open and closed", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      refute render(view) =~ "agent-grid-panel"
      html = render_click(view, "toggle_agent_grid", %{})
      assert html =~ "agent-grid-panel"
      html = render_click(view, "toggle_agent_grid", %{})
      refute html =~ "agent-grid-panel"
    end
  end
end
