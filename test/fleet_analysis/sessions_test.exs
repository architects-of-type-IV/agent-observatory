defmodule FleetAnalysis.SessionsTest do
  use ExUnit.Case, async: true

  import FleetAnalysis.TestEvents

  alias FleetAnalysis.Sessions

  describe "active_sessions/2" do
    test "groups events into one session per session id" do
      events = [
        event(session_id: "a"),
        event(session_id: "a"),
        event(session_id: "b")
      ]

      sessions = Sessions.active_sessions(events)

      assert length(sessions) == 2
      assert Enum.map(sessions, & &1.session_id) |> Enum.sort() == ["a", "b"]
    end

    test "counts events per session" do
      events = for _ <- 1..3, do: event(session_id: "a")

      assert [%{event_count: 3}] = Sessions.active_sessions(events)
    end

    test "separates the same session id under different apps" do
      events = [
        event(session_id: "a", source_app: "one"),
        event(session_id: "a", source_app: "two")
      ]

      assert length(Sessions.active_sessions(events)) == 2
    end

    test "orders sessions by most recent activity" do
      events = [
        event(session_id: "old", inserted_at: ago(600)),
        event(session_id: "new", inserted_at: ago(1))
      ]

      assert [%{session_id: "new"}, %{session_id: "old"}] = Sessions.active_sessions(events)
    end

    test "picks the newest event as latest and the oldest as first" do
      events = [
        event(session_id: "a", inserted_at: ago(100), tool_name: "first"),
        event(session_id: "a", inserted_at: ago(1), tool_name: "last")
      ]

      assert [session] = Sessions.active_sessions(events)
      assert session.latest_event.tool_name == "last"
      assert session.first_event.tool_name == "first"
    end

    test "marks a session ended when a SessionEnd event is present" do
      events = [
        event(session_id: "a"),
        event(session_id: "a", hook_event_type: :SessionEnd)
      ]

      assert [%{ended?: true}] = Sessions.active_sessions(events)
    end

    test "a session with no SessionEnd is not ended" do
      assert [%{ended?: false}] = Sessions.active_sessions([event(session_id: "a")])
    end

    test "finds the model from a payload" do
      events = [event(payload: %{"model" => "claude-opus-5"})]

      assert [%{model: "claude-opus-5"}] = Sessions.active_sessions(events)
    end

    test "falls back to model_name" do
      events = [event(payload: %{}, model_name: "haiku")]

      assert [%{model: "haiku"}] = Sessions.active_sessions(events)
    end

    test "finds a cwd from an earlier event when the latest lacks one" do
      events = [
        event(session_id: "a", inserted_at: ago(100), cwd: "/srv/project"),
        event(session_id: "a", inserted_at: ago(1), cwd: nil)
      ]

      assert [%{cwd: "/srv/project"}] = Sessions.active_sessions(events)
    end

    test "carries the permission mode from the latest event" do
      events = [
        event(session_id: "a", inserted_at: ago(100), permission_mode: "old"),
        event(session_id: "a", inserted_at: ago(1), permission_mode: "new")
      ]

      assert [%{permission_mode: "new"}] = Sessions.active_sessions(events)
    end

    test "an empty log yields no sessions" do
      assert Sessions.active_sessions([]) == []
    end
  end

  describe "tmux sessions with no events" do
    test "appear so a failed-to-start agent is visible" do
      sessions = Sessions.active_sessions([], tmux: ["ghost"], now: now())

      assert [%{session_id: "ghost", event_count: 0, ended?: false}] = sessions
    end

    test "are not duplicated when events already mention them" do
      events = [event(session_id: "a", tmux_session: "known")]

      sessions = Sessions.active_sessions(events, tmux: ["known"], now: now())

      assert length(sessions) == 1
      assert [%{session_id: "a"}] = sessions
    end

    test "mix with real sessions" do
      events = [event(session_id: "real", tmux_session: "real-tmux")]

      sessions = Sessions.active_sessions(events, tmux: ["real-tmux", "ghost"], now: now())

      ids = sessions |> Enum.map(& &1.session_id) |> Enum.sort()
      assert ids == ["ghost", "real"]
    end

    test "carry the supplied clock" do
      assert [%{latest_event: %{inserted_at: ts}}] =
               Sessions.active_sessions([], tmux: ["ghost"], now: now())

      assert ts == now()
    end
  end

  describe "malformed events" do
    test "an event missing most fields still groups" do
      assert [%{session_id: "a", event_count: 1}] =
               Sessions.active_sessions([%{session_id: "a", inserted_at: now()}])
    end

    test "an event with a non-map payload does not crash" do
      assert [%{model: nil}] = Sessions.active_sessions([event(payload: nil)])
    end
  end
end
