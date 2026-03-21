defmodule Ichor.Factory.PipelineTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ichor.Factory.Pipeline

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Ichor.Repo)
  end

  describe "create/1" do
    test "creates a pipeline with required attributes" do
      assert {:ok, pipeline} =
               Pipeline.create(%{label: "test-pipeline", source: :project})

      assert pipeline.label == "test-pipeline"
      assert pipeline.source == :project
      assert pipeline.status == :active
    end

    test "creates a pipeline with all optional attributes" do
      assert {:ok, pipeline} =
               Pipeline.create(%{
                 label: "imported-pipeline",
                 source: :imported,
                 project_path: "/tmp/myproject",
                 tmux_session: "tmux-abc"
               })

      assert pipeline.source == :imported
      assert pipeline.project_path == "/tmp/myproject"
      assert pipeline.tmux_session == "tmux-abc"
    end

    test "creates pipeline with genesis source" do
      assert {:ok, pipeline} = Pipeline.create(%{label: "genesis-pipeline", source: :genesis})
      assert pipeline.source == :genesis
    end

    test "rejects missing label" do
      assert {:error, _} = Pipeline.create(%{source: :project})
    end

    test "rejects missing source" do
      assert {:error, _} = Pipeline.create(%{label: "no-source"})
    end

    test "rejects invalid source enum" do
      assert {:error, _} = Pipeline.create(%{label: "bad-source", source: :invalid})
    end

    test "rejects invalid status enum" do
      assert {:error, _} =
               Pipeline.create(%{label: "bad-status", source: :project, status: :bogus})
    end

    test "defaults status to :active" do
      assert {:ok, pipeline} = Pipeline.create(%{label: "default-status", source: :project})
      assert pipeline.status == :active
    end
  end

  describe "get/1" do
    test "returns pipeline by id" do
      {:ok, created} = Pipeline.create(%{label: "get-test", source: :project})
      assert {:ok, fetched} = Pipeline.get(created.id)
      assert fetched.id == created.id
    end

    test "returns error for non-existent id" do
      assert {:error, _} = Pipeline.get(Ash.UUID.generate())
    end
  end

  describe "complete/1" do
    # Pipeline.complete emits :pipeline_completed signal. CompletionHandler (a GenServer
    # outside the Ecto sandbox) receives it and logs a warning when it cannot access the
    # sandbox connection. This is expected behaviour in test — capture the log to keep
    # output clean.
    test "sets status to :completed" do
      {:ok, pipeline} = Pipeline.create(%{label: "to-complete", source: :project})

      capture_log(fn ->
        assert {:ok, updated} = Pipeline.complete(pipeline)
        assert updated.status == :completed
        # brief pause for async signal delivery to CompletionHandler
        Process.sleep(50)
      end)
    end
  end

  describe "fail/1" do
    test "sets status to :failed" do
      {:ok, pipeline} = Pipeline.create(%{label: "to-fail", source: :project})

      capture_log(fn ->
        assert {:ok, updated} = Pipeline.fail(pipeline)
        assert updated.status == :failed
        Process.sleep(50)
      end)
    end
  end

  describe "archive/1" do
    test "sets status to :archived" do
      {:ok, pipeline} = Pipeline.create(%{label: "to-archive", source: :project})
      assert {:ok, updated} = Pipeline.archive(pipeline)
      assert updated.status == :archived
    end
  end

  describe "active/0" do
    test "returns only active pipelines" do
      {:ok, active} = Pipeline.create(%{label: "active-one", source: :project})
      {:ok, completed} = Pipeline.create(%{label: "completed-one", source: :project})

      capture_log(fn ->
        Pipeline.complete(completed)
        Process.sleep(50)
      end)

      assert {:ok, results} = Pipeline.active()
      ids = Enum.map(results, & &1.id)
      assert active.id in ids
      refute completed.id in ids
    end
  end

  describe "by_project/1" do
    test "returns active pipelines for a project_id" do
      pid = "proj-#{:rand.uniform(999_999)}"
      {:ok, p1} = Pipeline.create(%{label: "proj-run-1", source: :project, project_id: pid})
      {:ok, p2} = Pipeline.create(%{label: "proj-run-2", source: :project, project_id: pid})
      {:ok, other} = Pipeline.create(%{label: "other", source: :project, project_id: "other-id"})

      assert {:ok, results} = Pipeline.by_project(pid)
      ids = Enum.map(results, & &1.id)
      assert p1.id in ids
      assert p2.id in ids
      refute other.id in ids
    end

    test "excludes completed pipelines" do
      pid = "proj-#{:rand.uniform(999_999)}"
      {:ok, done} = Pipeline.create(%{label: "done-run", source: :project, project_id: pid})

      capture_log(fn ->
        Pipeline.complete(done)
        Process.sleep(50)
      end)

      assert {:ok, results} = Pipeline.by_project(pid)
      refute done.id in Enum.map(results, & &1.id)
    end
  end

  describe "by_path/1" do
    test "returns active pipelines for a project_path" do
      path = "/tmp/test-path-#{:rand.uniform(999_999)}"
      {:ok, p} = Pipeline.create(%{label: "path-run", source: :imported, project_path: path})

      assert {:ok, results} = Pipeline.by_path(path)
      assert p.id in Enum.map(results, & &1.id)
    end
  end

  describe "get_run_status/1" do
    test "returns status map for a pipeline" do
      {:ok, pipeline} = Pipeline.create(%{label: "status-test", source: :project})

      assert {:ok, result} = Pipeline.get_run_status(pipeline.id)
      assert result["run_id"] == pipeline.id
      assert result["label"] == "status-test"
      assert result["status"] == "active"
      assert result["source"] == "project"
      assert result["task_count"] == 0
      assert result["stats"]["total"] == 0
    end

    test "returns error for non-existent run_id" do
      assert {:error, _} = Pipeline.get_run_status(Ash.UUID.generate())
    end
  end

  describe "export_jsonl/1" do
    test "returns empty jsonl for pipeline with no tasks" do
      {:ok, pipeline} = Pipeline.create(%{label: "export-test", source: :project})

      assert {:ok, result} = Pipeline.export_jsonl(pipeline.id)
      assert result["run_id"] == pipeline.id
      assert result["jsonl"] == ""
    end
  end
end
