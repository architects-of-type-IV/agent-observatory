defmodule Ichor.Dag.AnalysisTest do
  use ExUnit.Case, async: true

  alias Ichor.Dag.Analysis

  test "computes pipeline counts" do
    tasks = [
      %{id: "1", status: "pending", blocked_by: [], files: []},
      %{id: "2", status: "in_progress", blocked_by: ["1"], files: ["a.ex"]},
      %{id: "3", status: "in_progress", blocked_by: ["2"], files: ["a.ex"]}
    ]

    pipeline = Analysis.compute_pipeline(tasks)
    dag = Analysis.compute_dag(tasks)

    stale =
      Analysis.find_stale_tasks(
        [Map.put(Enum.at(tasks, 1), :updated, "2020-01-01T00:00:00Z")],
        DateTime.utc_now()
      )

    conflicts = Analysis.find_file_conflicts(tasks)

    assert pipeline.pending == 1
    assert pipeline.in_progress == 2
    assert pipeline.completed == 0
    assert dag.edges == [{"1", "2"}, {"2", "3"}]
    assert stale != []
    assert conflicts == [{"2", "3", ["a.ex"]}]
  end
end
