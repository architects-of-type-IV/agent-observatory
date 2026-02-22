defmodule ObservatoryWeb.SessionClusterTest do
  use ObservatoryWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "Session Cluster view" do
    test "renders session cluster view", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "session_cluster"})
      assert html =~ "session-cluster-view"
    end

    test "select_session sets selected_session_id and shows drill-down panels", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "session_cluster"})
      html = render_click(view, "select_session", %{"session_id" => "sess-xyz-789"})
      assert html =~ "causal-dag-panel"
      assert html =~ "live-scratchpad-panel"
      assert html =~ "hitl-console-panel"
    end

    test "entropy filter with no high-entropy sessions shows empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "session_cluster"})
      html = render_click(view, "toggle_entropy_filter", %{})
      assert html =~ "No high-entropy sessions."
    end
  end

  describe "Registry view" do
    test "renders registry view", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "registry"})
      assert html =~ "registry-view"
      assert html =~ "Capability Directory"
      assert html =~ "Routing Logic Manager"
    end

    test "update_route_weight with valid value succeeds", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "registry"})
      html = render_click(view, "update_route_weight", %{"agent_type" => "worker", "weight" => "70"})
      refute html =~ "Must be 0-100"
    end

    test "update_route_weight with invalid value does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "registry"})
      html = render_click(view, "update_route_weight", %{"agent_type" => "worker", "weight" => "-1"})
      assert html =~ "registry-view"
    end
  end
end
