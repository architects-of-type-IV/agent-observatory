defmodule ObservatoryWeb.SessionDrilldownLiveTest do
  use ObservatoryWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Observatory.Gateway.HITLRelay

  setup do
    :ets.delete_all_objects(:hitl_buffer)
    :ok
  end

  defp mount_drilldown(conn, session_id) do
    live_isolated(conn, ObservatoryWeb.SessionDrilldownLive,
      session: %{"session_id" => session_id}
    )
  end

  describe "mount" do
    test "renders session id and normal status", %{conn: conn} do
      sid = "drilldown-#{System.unique_integer([:positive])}"
      {:ok, view, html} = mount_drilldown(conn, sid)

      assert html =~ sid
      assert html =~ "normal"
      assert has_element?(view, "h2", "Session: #{sid}")
    end

    test "shows paused status when session is paused", %{conn: conn} do
      sid = "paused-dd-#{System.unique_integer([:positive])}"
      HITLRelay.pause(sid, "agent-1", "operator-1", "review")

      {:ok, _view, html} = mount_drilldown(conn, sid)

      assert html =~ "paused"
    end
  end

  describe "approve" do
    test "unpauses session and shows flash", %{conn: conn} do
      sid = "approve-dd-#{System.unique_integer([:positive])}"
      HITLRelay.pause(sid, "agent-1", "operator-1", "review")

      {:ok, view, _html} = mount_drilldown(conn, sid)

      html = view |> element("button", "Approve") |> render_click()

      assert html =~ "Approved. Flushed 0 messages."
      assert html =~ "normal"
    end
  end

  describe "reject" do
    test "unpauses session with rejection reason", %{conn: conn} do
      sid = "reject-dd-#{System.unique_integer([:positive])}"
      HITLRelay.pause(sid, "agent-1", "operator-1", "review")

      {:ok, view, _html} = mount_drilldown(conn, sid)

      html =
        view
        |> form("form[phx-submit=reject]", %{"reason" => "bad output"})
        |> render_submit()

      assert html =~ "Rejected. Reason: bad output"
    end
  end

  describe "PubSub updates" do
    test "updates status when HITL event received", %{conn: conn} do
      sid = "pubsub-dd-#{System.unique_integer([:positive])}"
      {:ok, view, _html} = mount_drilldown(conn, sid)

      # Pause the session externally
      HITLRelay.pause(sid, "agent-1", "operator-1", "review")

      # The PubSub message should trigger handle_info
      html = render(view)
      assert html =~ "paused"
    end
  end
end
