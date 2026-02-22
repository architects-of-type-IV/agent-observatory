defmodule ObservatoryWeb.DashboardLiveTest do
  use ObservatoryWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Phase 5 navigation shell" do
    test "mounts with fleet_command as default view_mode", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "fleet-command-view"
    end

    test "set_view switches to session_cluster", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "session_cluster"})
      assert html =~ "session-cluster-view"
    end

    test "set_view switches to registry", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "registry"})
      assert html =~ "registry-view"
    end

    test "set_view switches to scheduler", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "scheduler"})
      assert html =~ "scheduler-view"
    end

    test "set_view switches to forensic", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "forensic"})
      assert html =~ "forensic-view"
    end

    test "set_view switches to god_mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "god_mode"})
      assert html =~ "god-mode-view"
    end

    test "restore_view_mode with valid value restores scheduler", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "restore_view_mode", %{"value" => "scheduler"})
      assert html =~ "scheduler-view"
    end

    test "restore_view_mode with invalid value falls back to fleet_command", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "restore_view_mode", %{"value" => "command"})
      assert html =~ "fleet-command-view"
    end
  end

  describe "Scheduler view" do
    test "renders scheduler view with all panels", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "scheduler"})
      assert html =~ "scheduler-view"
      assert html =~ "Cron Job Dashboard"
      assert html =~ "Dead Letter Queue"
      assert html =~ "Heartbeat Monitor"
    end

    test "empty DLQ shows empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "scheduler"})
      assert html =~ "No failed deliveries."
    end
  end

  describe "Forensic view" do
    test "renders forensic view with all panels", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "forensic"})
      assert html =~ "forensic-view"
      assert html =~ "message-archive-panel"
      assert html =~ "cost-attribution-panel"
      assert html =~ "security-panel"
      assert html =~ "policy-engine-panel"
    end

    test "set_cost_group_by to session_id updates grouping", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "forensic"})
      html = render_click(view, "set_cost_group_by", %{"field" => "session_id"})
      assert html =~ "forensic-view"
    end

    test "search archive with no match shows empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "forensic"})
      html = render_click(view, "search_archive", %{"q" => "nonexistent_query_xyz"})
      assert html =~ "No matching messages found."
    end
  end
end
