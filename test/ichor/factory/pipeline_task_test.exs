defmodule Ichor.Factory.PipelineTaskTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Ichor.Factory.{Pipeline, PipelineTask}

  setup do
    Sandbox.checkout(Ichor.Repo)
    {:ok, pipeline} = Pipeline.create(%{label: "task-test-pipeline", source: :project})
    {:ok, pipeline: pipeline}
  end

  defp task_attrs(pipeline, overrides \\ %{}) do
    Map.merge(
      %{
        external_id: "1",
        subject: "Test task",
        run_id: pipeline.id
      },
      overrides
    )
  end

  describe "create/1" do
    test "creates a task with required attributes", %{pipeline: pipeline} do
      assert {:ok, task} = PipelineTask.create(task_attrs(pipeline))

      assert task.external_id == "1"
      assert task.subject == "Test task"
      assert task.run_id == pipeline.id
      assert task.status == :pending
      assert task.priority == :medium
    end

    test "creates task with all optional attributes", %{pipeline: pipeline} do
      assert {:ok, task} =
               PipelineTask.create(
                 task_attrs(pipeline, %{
                   external_id: "2",
                   description: "Do the thing",
                   goal: "Thing is done",
                   allowed_files: ["lib/foo.ex"],
                   steps: ["step 1", "step 2"],
                   done_when: "mix test",
                   blocked_by: ["1"],
                   priority: :high,
                   wave: 2,
                   acceptance_criteria: ["criterion 1"],
                   phase_label: "Phase 1",
                   tags: ["backend"],
                   notes: "initial notes"
                 })
               )

      assert task.description == "Do the thing"
      assert task.goal == "Thing is done"
      assert task.allowed_files == ["lib/foo.ex"]
      assert task.steps == ["step 1", "step 2"]
      assert task.done_when == "mix test"
      assert task.blocked_by == ["1"]
      assert task.priority == :high
      assert task.wave == 2
      assert task.acceptance_criteria == ["criterion 1"]
      assert task.phase_label == "Phase 1"
      assert task.tags == ["backend"]
    end

    test "rejects missing external_id", %{pipeline: pipeline} do
      assert {:error, _} = PipelineTask.create(%{subject: "no-external-id", run_id: pipeline.id})
    end

    test "rejects missing subject", %{pipeline: pipeline} do
      assert {:error, _} = PipelineTask.create(%{external_id: "1", run_id: pipeline.id})
    end

    test "rejects missing run_id" do
      assert {:error, _} = PipelineTask.create(%{external_id: "1", subject: "orphan"})
    end

    test "rejects invalid priority enum", %{pipeline: pipeline} do
      assert {:error, _} =
               PipelineTask.create(task_attrs(pipeline, %{priority: :urgent}))
    end

    test "rejects invalid status enum", %{pipeline: pipeline} do
      assert {:error, _} =
               PipelineTask.create(task_attrs(pipeline, %{status: :blocked}))
    end

    test "defaults status to :pending and priority to :medium", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      assert task.status == :pending
      assert task.priority == :medium
    end
  end

  describe "get/1" do
    test "returns task by id", %{pipeline: pipeline} do
      {:ok, created} = PipelineTask.create(task_attrs(pipeline))
      assert {:ok, fetched} = PipelineTask.get(created.id)
      assert fetched.id == created.id
    end

    test "returns error for non-existent id" do
      assert {:error, _} = PipelineTask.get(Ash.UUID.generate())
    end
  end

  describe "by_run/1" do
    test "returns tasks for a pipeline", %{pipeline: pipeline} do
      {:ok, t1} = PipelineTask.create(task_attrs(pipeline, %{external_id: "1"}))
      {:ok, t2} = PipelineTask.create(task_attrs(pipeline, %{external_id: "2"}))

      {:ok, other_pipeline} = Pipeline.create(%{label: "other-pipeline", source: :project})
      {:ok, _t3} = PipelineTask.create(task_attrs(other_pipeline, %{external_id: "1"}))

      assert {:ok, tasks} = PipelineTask.by_run(pipeline.id)
      ids = Enum.map(tasks, & &1.id)
      assert t1.id in ids
      assert t2.id in ids
      assert length(tasks) == 2
    end
  end

  describe "available/1" do
    test "returns only pending unclaimed tasks", %{pipeline: pipeline} do
      {:ok, pending} = PipelineTask.create(task_attrs(pipeline, %{external_id: "1"}))
      {:ok, owned} = PipelineTask.create(task_attrs(pipeline, %{external_id: "2"}))
      PipelineTask.claim(owned, "agent-1")

      assert {:ok, available} = PipelineTask.available(pipeline.id)
      ids = Enum.map(available, & &1.id)
      assert pending.id in ids
      refute owned.id in ids
    end
  end

  describe "claim/2" do
    test "claims a pending task", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      assert {:ok, claimed} = PipelineTask.claim(task, "agent-session-1")
      assert claimed.status == :in_progress
      assert claimed.owner == "agent-session-1"
      assert claimed.claimed_at != nil
    end

    test "rejects claiming an already-claimed task", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      {:ok, _} = PipelineTask.claim(task, "agent-1")

      {:ok, fresh} = PipelineTask.get(task.id)
      assert {:error, _} = PipelineTask.claim(fresh, "agent-2")
    end
  end

  describe "complete/1" do
    test "sets status to :completed", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      assert {:ok, done} = PipelineTask.complete(task)
      assert done.status == :completed
      assert done.completed_at != nil
    end

    test "can complete with notes", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      assert {:ok, done} = PipelineTask.complete(task, %{notes: "all good"})
      assert done.notes == "all good"
    end
  end

  describe "fail/1" do
    test "sets status to :failed", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      assert {:ok, failed} = PipelineTask.fail(task, %{notes: "it broke"})
      assert failed.status == :failed
      assert failed.notes == "it broke"
    end
  end

  describe "reset/1" do
    test "resets an in-progress task to pending", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      {:ok, claimed} = PipelineTask.claim(task, "agent-1")
      assert {:ok, reset} = PipelineTask.reset(claimed)
      assert reset.status == :pending
      assert reset.owner == nil
      assert reset.claimed_at == nil
    end
  end

  describe "reassign/2" do
    test "changes the owner", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      {:ok, claimed} = PipelineTask.claim(task, "agent-1")
      assert {:ok, reassigned} = PipelineTask.reassign(claimed, "agent-2")
      assert reassigned.owner == "agent-2"
    end
  end

  describe "next_tasks/1 (generic action)" do
    test "returns available task maps for a run", %{pipeline: pipeline} do
      {:ok, _t1} = PipelineTask.create(task_attrs(pipeline, %{external_id: "1"}))
      {:ok, t2} = PipelineTask.create(task_attrs(pipeline, %{external_id: "2"}))
      # Claim t2 so it's no longer available
      {:ok, fresh_t2} = PipelineTask.get(t2.id)
      PipelineTask.claim(fresh_t2, "agent-1")

      assert {:ok, available} = PipelineTask.next_tasks(pipeline.id)
      assert is_list(available)
      # t2 is claimed, so only t1 should be available
      assert length(available) == 1
      assert hd(available)["external_id"] == "1"
    end
  end

  describe "claim_task/2 (generic action)" do
    test "claims a task and returns a map", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      assert {:ok, result} = PipelineTask.claim_task(task.id, "agent-session")
      assert result["status"] == "in_progress"
      assert result["owner"] == "agent-session"
    end

    test "rejects claiming an already-claimed task", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      PipelineTask.claim_task(task.id, "agent-1")
      assert {:error, _} = PipelineTask.claim_task(task.id, "agent-2")
    end
  end

  describe "complete_task/1 (generic action)" do
    test "completes a task and reports unblocked tasks", %{pipeline: pipeline} do
      {:ok, t1} =
        PipelineTask.create(task_attrs(pipeline, %{external_id: "1", subject: "First"}))

      {:ok, _t2} =
        PipelineTask.create(
          task_attrs(pipeline, %{
            external_id: "2",
            subject: "Second",
            blocked_by: ["1"]
          })
        )

      assert {:ok, result} = PipelineTask.complete_task(t1.id)
      assert result["completed"]["external_id"] == "1"
      # t2 should now be unblocked
      assert length(result["newly_unblocked"]) == 1
      assert hd(result["newly_unblocked"])["external_id"] == "2"
    end
  end

  describe "fail_task/2 (generic action)" do
    test "marks a task as failed with notes", %{pipeline: pipeline} do
      {:ok, task} = PipelineTask.create(task_attrs(pipeline))
      assert {:ok, result} = PipelineTask.fail_task(task.id, "build failed")
      assert result["status"] == "failed"
    end
  end
end
