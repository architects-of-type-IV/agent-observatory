defmodule ObservatoryWeb.FleetCommandTest do
  use ObservatoryWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "single-screen observatory" do
    test "renders topology canvas on mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "fleet-topology-hook"
      assert html =~ "TopologyMap"
    end

    test "renders feed on mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Waiting for agent activity"
    end

    test "renders fleet status bar", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "OK"
    end
  end
end
