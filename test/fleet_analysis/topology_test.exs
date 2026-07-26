defmodule FleetAnalysis.TopologyTest do
  use ExUnit.Case, async: false

  import FleetAnalysis.TestEvents

  alias FleetAnalysis.Sessions
  alias FleetAnalysis.Topology

  doctest FleetAnalysis.Topology

  setup do
    on_exit(fn -> Application.delete_env(:fleet_analysis, :idle_after_sec) end)
    :ok
  end

  defp sessions_for(events), do: Sessions.active_sessions(events)

  describe "state/2" do
    test "an ended session is dead" do
      assert Topology.state(%{ended?: true, latest_event: %{inserted_at: now()}}, now()) == "dead"
    end

    test "recent activity is active" do
      session = %{ended?: false, latest_event: %{inserted_at: ago(5)}}

      assert Topology.state(session, now()) == "active"
    end

    test "old activity is idle" do
      session = %{ended?: false, latest_event: %{inserted_at: ago(600)}}

      assert Topology.state(session, now()) == "idle"
    end

    test "dead outranks idle" do
      session = %{ended?: true, latest_event: %{inserted_at: ago(600)}}

      assert Topology.state(session, now()) == "dead"
    end

    test "honours a configured idle threshold" do
      Application.put_env(:fleet_analysis, :idle_after_sec, 10)
      session = %{ended?: false, latest_event: %{inserted_at: ago(30)}}

      assert Topology.state(session, now()) == "idle"
    end
  end

  describe "duration/1" do
    test "renders seconds, minutes, and hours" do
      assert Topology.duration(0) == "0s"
      assert Topology.duration(59) == "59s"
      assert Topology.duration(60) == "1m"
      assert Topology.duration(3599) == "59m"
      assert Topology.duration(3600) == "1h0m"
      assert Topology.duration(7325) == "2h2m"
    end
  end

  describe "short_model/1" do
    test "recognises the model families" do
      assert Topology.short_model("claude-opus-5") == "opus"
      assert Topology.short_model("claude-sonnet-5") == "sonnet"
      assert Topology.short_model("claude-haiku-4-5-20251001") == "haiku"
    end

    test "falls back to the first segment" do
      assert Topology.short_model("gpt-4o") == "gpt"
      assert Topology.short_model("mistral") == "mistral"
    end

    test "passes nil through" do
      assert Topology.short_model(nil) == nil
    end
  end

  describe "build/3 session nodes" do
    test "emits one node per session" do
      sessions = sessions_for([event(session_id: "a"), event(session_id: "b")])

      {nodes, _edges} = Topology.build(sessions, [], now())

      assert length(nodes) == 2
    end

    test "labels a node from its team role when there is one" do
      sessions = sessions_for([event(session_id: "a")])
      teams = [team("alpha", [member(agent_id: "a", name: "builder")])]

      {[node], _} = Topology.build(sessions, teams, now())

      assert node.label == "builder"
      assert node.team == "alpha"
    end

    test "falls back to the source app when the session is in no team" do
      sessions = sessions_for([event(session_id: "a", source_app: "my-app")])

      {[node], _} = Topology.build(sessions, [], now())

      assert node.label == "my-app"
      assert node.team == nil
    end

    test "falls back to a short id when there is no app either" do
      sessions =
        sessions_for([event(session_id: "550e8400-e29b-41d4-a716-446655440000", source_app: nil)])

      {[node], _} = Topology.build(sessions, [], now())

      assert node.label == "550e8400"
    end

    test "shortens the model and basenames the cwd" do
      sessions =
        sessions_for([event(payload: %{"model" => "claude-opus-5"}, cwd: "/srv/my-project")])

      {[node], _} = Topology.build(sessions, [], now())

      assert node.model == "opus"
      assert node.cwd == "my-project"
    end

    test "measures duration from the first event" do
      sessions =
        sessions_for([
          event(session_id: "a", inserted_at: ago(300)),
          event(session_id: "a", inserted_at: ago(10))
        ])

      {[node], _} = Topology.build(sessions, [], now())

      assert node.duration == "5m"
    end
  end

  describe "build/3 orphan member nodes" do
    test "a configured member with no session still gets a node" do
      teams = [team("alpha", [member(agent_id: "never-started", name: "builder")])]

      {nodes, _} = Topology.build([], teams, now())

      assert [%{agent_id: "never-started", label: "builder", team: "alpha"}] = nodes
    end

    test "a member with a live session is not duplicated" do
      sessions = sessions_for([event(session_id: "running")])
      teams = [team("alpha", [member(agent_id: "running", name: "builder")])]

      {nodes, _} = Topology.build(sessions, teams, now())

      assert length(nodes) == 1
    end

    test "an orphan node has no duration, since it never ran" do
      teams = [team("alpha", [member(agent_id: "ghost")])]

      {[node], _} = Topology.build([], teams, now())

      assert node.duration == nil
    end

    test "an orphan node carries its configured status" do
      teams = [team("alpha", [member(agent_id: "ghost", status: :pending)])]

      {[node], _} = Topology.build([], teams, now())

      assert node.state == "pending"
    end

    test "a member with no agent_id is skipped" do
      teams = [team("alpha", [member(agent_id: nil)])]

      {nodes, _} = Topology.build([], teams, now())

      assert nodes == []
    end

    test "falls back from name to agent_type for the label" do
      teams = [team("alpha", [member(agent_id: "g", name: nil, agent_type: "scout")])]

      {[node], _} = Topology.build([], teams, now())

      assert node.label == "scout"
    end
  end

  describe "build/3 edges" do
    test "chains consecutive members of a team" do
      teams = [
        team("alpha", [
          member(agent_id: "a"),
          member(agent_id: "b"),
          member(agent_id: "c")
        ])
      ]

      {_nodes, edges} = Topology.build([], teams, now())

      assert [%{from: "a", to: "b"}, %{from: "b", to: "c"}] = edges
    end

    test "a single-member team has no edges" do
      teams = [team("alpha", [member(agent_id: "a")])]

      {_nodes, edges} = Topology.build([], teams, now())

      assert edges == []
    end

    test "members with no agent_id are dropped before chaining" do
      teams = [
        team("alpha", [member(agent_id: "a"), member(agent_id: nil), member(agent_id: "c")])
      ]

      {_nodes, edges} = Topology.build([], teams, now())

      assert [%{from: "a", to: "c"}] = edges
    end

    test "no teams means no edges" do
      {_nodes, edges} = Topology.build(sessions_for([event()]), [], now())

      assert edges == []
    end
  end

  describe "malformed teams" do
    test "a team with no members list does not crash" do
      {nodes, edges} = Topology.build([], [%{name: "alpha"}], now())

      assert nodes == []
      assert edges == []
    end

    test "a team with no name yields nil team on its nodes" do
      {[node], _} = Topology.build([], [%{members: [member(agent_id: "a")]}], now())

      assert node.team == nil
    end
  end
end
