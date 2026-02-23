defmodule ObservatoryWeb.SessionClusterTest do
  use ObservatoryWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "session and registry handlers" do
    test "select_session handler does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_session", %{"session_id" => "sess-xyz-789"})
      assert html =~ "Observatory"
    end

    test "toggle_entropy_filter handler does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "toggle_entropy_filter", %{})
      assert html =~ "Observatory"
    end

    test "update_route_weight with valid value does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "update_route_weight", %{"agent_type" => "worker", "weight" => "70"})
      assert html =~ "Observatory"
    end

    test "update_route_weight with invalid value does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "update_route_weight", %{"agent_type" => "worker", "weight" => "-1"})
      assert html =~ "Observatory"
    end
  end
end
