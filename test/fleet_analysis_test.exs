defmodule FleetAnalysisTest do
  use ExUnit.Case, async: true

  import FleetAnalysis.TestEvents

  doctest FleetAnalysis.Entry
  doctest FleetAnalysis.Event

  describe "Entry" do
    alias FleetAnalysis.Entry

    test "new/1 builds a default entry reachable on its mailbox" do
      entry = Entry.new("pipeline-abc-builder")

      assert entry.session_id == "pipeline-abc-builder"
      assert entry.id == "pipeline-abc-builder"
      assert entry.role == :standalone
      assert entry.status == :active
      assert entry.channels.mailbox == "pipeline-abc-builder"
      assert entry.channels.tmux == nil
    end

    test "new/1 shortens a UUID id" do
      entry = Entry.new("550e8400-e29b-41d4-a716-446655440000")

      assert entry.id == "550e8400"
      assert entry.session_id == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "short_id/1 handles empty and non-binary input" do
      assert Entry.short_id("") == "?"
      assert Entry.short_id(nil) == "?"
      assert Entry.short_id(:atom) == "?"
    end

    test "uuid?/1 rejects near-misses" do
      refute Entry.uuid?("550e8400e29b41d4a716446655440000")
      refute Entry.uuid?("550e8400-e29b-41d4-a716")
      refute Entry.uuid?(nil)
    end

    test "role_from_string/1 maps known roles" do
      assert Entry.role_from_string("team-lead") == :lead
      assert Entry.role_from_string("lead") == :lead
      assert Entry.role_from_string("coordinator") == :coordinator
    end

    test "role_from_string/1 bounds unknown input rather than creating atoms" do
      before = :erlang.system_info(:atom_count)

      assert Entry.role_from_string("a-role-that-has-never-existed") == :worker
      assert Entry.role_from_string("") == :worker

      # The input is user-authored team config, so an unbounded String.to_atom/1
      # here would be an atom-table leak.
      assert :erlang.system_info(:atom_count) == before
    end
  end

  describe "health_by_session/2" do
    test "analyses each session separately" do
      events = [
        event(session_id: "healthy", inserted_at: ago(1)),
        event(session_id: "stuck", inserted_at: ago(600))
      ]

      result = FleetAnalysis.health_by_session(events, now())

      assert result["healthy"].health == :healthy
      assert result["stuck"].health == :critical
    end

    test "drops events with no session id" do
      events = [event(session_id: nil), event(session_id: "a")]

      result = FleetAnalysis.health_by_session(events, now())

      assert Map.keys(result) == ["a"]
    end

    test "an empty log yields an empty map" do
      assert FleetAnalysis.health_by_session([], now()) == %{}
    end
  end

  describe "unhealthy/2" do
    test "returns only sessions needing attention" do
      events = [
        event(session_id: "fine", inserted_at: ago(1)),
        event(session_id: "stuck", inserted_at: ago(600))
      ]

      assert [{"stuck", %{health: :critical}}] = FleetAnalysis.unhealthy(events, now())
    end

    test "sorts critical before warning" do
      warning =
        [event(session_id: "warn", hook_event_type: :PostToolUseFailure, inserted_at: ago(1))] ++
          for(
            _ <- 1..2,
            do: event(session_id: "warn", hook_event_type: :PostToolUse, inserted_at: ago(1))
          )

      events = warning ++ [event(session_id: "crit", inserted_at: ago(600))]

      assert [{"crit", _}, {"warn", _}] = FleetAnalysis.unhealthy(events, now())
    end

    test "a healthy fleet reports nothing" do
      assert FleetAnalysis.unhealthy([event(inserted_at: ago(1))], now()) == []
    end
  end

  describe "delegation" do
    test "health/2 delegates to Health.compute/2" do
      assert %{health: :critical} = FleetAnalysis.health([event(inserted_at: ago(600))], now())
    end

    test "sessions/2 delegates to Sessions.active_sessions/2" do
      assert [%{session_id: "a"}] = FleetAnalysis.sessions([event(session_id: "a")])
    end

    test "topology/3 delegates to Topology.build/3" do
      sessions = FleetAnalysis.sessions([event(session_id: "a")])

      assert {[%{agent_id: "a"}], []} = FleetAnalysis.topology(sessions, [], now())
    end
  end

  describe "end to end" do
    test "a fleet with one stuck agent and one orphan renders both" do
      events = [
        event(session_id: "running", inserted_at: ago(1), source_app: "app"),
        event(session_id: "stalled", inserted_at: ago(600), source_app: "app")
      ]

      teams = [
        team("alpha", [
          member(agent_id: "running", name: "builder"),
          member(agent_id: "stalled", name: "scout"),
          member(agent_id: "never-started", name: "planner")
        ])
      ]

      sessions = FleetAnalysis.sessions(events)
      {nodes, edges} = FleetAnalysis.topology(sessions, teams, now())

      labels = nodes |> Enum.map(& &1.label) |> Enum.sort()
      assert labels == ["builder", "planner", "scout"]

      assert length(edges) == 2

      assert [{"stalled", %{issues: [{:stuck, _}]}}] = FleetAnalysis.unhealthy(events, now())
    end
  end
end
