defmodule Ichor.Dag.HandoffTest do
  use ExUnit.Case, async: true

  alias Ichor.Dag.Handoff

  test "packages jobs into wave-grouped handoff data" do
    jobs = [
      %{
        id: "j-2",
        external_id: "2",
        wave: 1,
        subject: "Two",
        description: "d2",
        goal: "g2",
        allowed_files: ["b.ex"],
        steps: ["s2"],
        done_when: "mix test",
        blocked_by: ["1"],
        owner: nil,
        priority: :medium,
        acceptance_criteria: ["a2"],
        phase_label: "phase-1",
        tags: ["backend"],
        notes: nil
      },
      %{
        id: "j-1",
        external_id: "1",
        wave: 0,
        subject: "One",
        description: "d1",
        goal: "g1",
        allowed_files: ["a.ex"],
        steps: ["s1"],
        done_when: "mix compile",
        blocked_by: [],
        owner: "worker-1",
        priority: :high,
        acceptance_criteria: ["a1"],
        phase_label: "phase-1",
        tags: [],
        notes: "n1"
      }
    ]

    handoff = Handoff.package_jobs("run-1", jobs)

    assert handoff.run_id == "run-1"
    assert Map.keys(handoff.waves) == [0, 1]
    assert Enum.map(handoff.jobs, & &1.external_id) == ["1", "2"]
    assert hd(handoff.waves[0]).owner == "worker-1"
  end
end
