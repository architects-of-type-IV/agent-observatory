defmodule ObservatoryWeb.GodModeTest do
  use ObservatoryWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "God Mode view" do
    test "renders god mode view with kill switch", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "god_mode"})
      assert html =~ "god-mode-view"
      assert html =~ "god-mode-panel"
      assert html =~ "god-mode-button-danger"
      assert html =~ "Emergency Kill Switch"
    end

    test "does not render primary-button class", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "set_view", %{"mode" => "god_mode"})
      refute html =~ "primary-button"
    end

    test "kill switch click shows first confirmation", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "god_mode"})
      html = render_click(view, "kill_switch_click", %{})
      assert html =~ "Are you sure?"
      assert html =~ "Yes, proceed"
    end

    test "kill switch first confirm shows final confirmation", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "god_mode"})
      render_click(view, "kill_switch_click", %{})
      html = render_click(view, "kill_switch_first_confirm", %{})
      assert html =~ "FINAL CONFIRMATION"
      assert html =~ "CONFIRM KILL"
    end

    test "kill switch cancel resets to initial state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "god_mode"})
      render_click(view, "kill_switch_click", %{})
      html = render_click(view, "kill_switch_cancel", %{})
      assert html =~ "Emergency Kill Switch"
      refute html =~ "Are you sure?"
    end

    test "kill switch full sequence completes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "god_mode"})
      render_click(view, "kill_switch_click", %{})
      render_click(view, "kill_switch_first_confirm", %{})
      html = render_click(view, "kill_switch_second_confirm", %{})
      assert html =~ "Emergency Kill Switch"
      refute html =~ "FINAL CONFIRMATION"
    end

    test "spurious second confirm without first resets", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "set_view", %{"mode" => "god_mode"})
      html = render_click(view, "kill_switch_second_confirm", %{})
      assert html =~ "Emergency Kill Switch"
    end
  end
end
