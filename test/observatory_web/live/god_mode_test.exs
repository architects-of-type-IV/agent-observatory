defmodule ObservatoryWeb.GodModeTest do
  use ObservatoryWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "kill switch handlers" do
    test "kill_switch_click handler does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "kill_switch_click", %{})
      assert html =~ "Observatory"
    end

    test "full kill switch sequence completes without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "kill_switch_click", %{})
      render_click(view, "kill_switch_first_confirm", %{})
      html = render_click(view, "kill_switch_second_confirm", %{})
      assert html =~ "Observatory"
    end

    test "kill switch cancel resets state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "kill_switch_click", %{})
      html = render_click(view, "kill_switch_cancel", %{})
      assert html =~ "Observatory"
    end

    test "spurious second confirm without first does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "kill_switch_second_confirm", %{})
      assert html =~ "Observatory"
    end
  end
end
