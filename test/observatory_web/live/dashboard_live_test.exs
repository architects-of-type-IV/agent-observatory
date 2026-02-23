defmodule ObservatoryWeb.DashboardLiveTest do
  use ObservatoryWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "single-screen layout" do
    test "mounts with topology and feed visible", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "fleet-topology-hook"
      assert html =~ "Waiting for agent activity"
    end

    test "renders search bar and filter presets", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Search events"
      assert html =~ "Failed Tools"
      assert html =~ "Team Events"
      assert html =~ "Errors Only"
    end

    test "renders header with Observatory title", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Observatory"
      assert html =~ "live"
    end

    test "renders sidebar with sessions section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Sessions"
      assert html =~ "Search sessions"
    end

    test "legacy view mode handlers do not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # These handlers still exist but screens are merged -- verify no crash
      render_click(view, "set_view", %{"mode" => "feed"})
      render_click(view, "set_view", %{"mode" => "scheduler"})
      render_click(view, "set_view", %{"mode" => "god_mode"})
      render_click(view, "set_view", %{"mode" => "forensic"})
      render_click(view, "set_view", %{"mode" => "pipeline"})
      render_click(view, "set_view", %{"mode" => "command"})
      html = render_click(view, "restore_view_mode", %{"value" => "nonexistent"})
      assert html =~ "Observatory"
    end
  end

  describe "search and filters" do
    test "search_feed updates search term", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_change(view, "search_feed", %{"q" => "test_query"})
      assert html =~ "test_query"
    end

    test "apply_preset fires without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "apply_preset", %{"preset" => "failed_tools"})
      assert html =~ "Observatory"
    end

    test "clear_filters resets state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "clear_filters", %{})
      assert html =~ "Observatory"
    end
  end

  describe "kill switch handlers" do
    test "kill switch state machine cycles without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "kill_switch_click", %{})
      render_click(view, "kill_switch_first_confirm", %{})
      render_click(view, "kill_switch_second_confirm", %{})
      html = render(view)
      assert html =~ "Observatory"
    end

    test "kill switch cancel resets", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "kill_switch_click", %{})
      render_click(view, "kill_switch_cancel", %{})
      html = render(view)
      assert html =~ "Observatory"
    end
  end
end
