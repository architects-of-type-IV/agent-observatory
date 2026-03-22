defmodule Ichor.Factory.CronJobTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Ichor.Factory.CronJob

  setup do
    Sandbox.checkout(Ichor.Repo)
  end

  defp future_time(offset_seconds \\ 3600) do
    DateTime.utc_now() |> DateTime.add(offset_seconds, :second) |> DateTime.truncate(:second)
  end

  defp past_time(offset_seconds \\ 3600) do
    DateTime.utc_now() |> DateTime.add(-offset_seconds, :second) |> DateTime.truncate(:second)
  end

  describe "schedule_once/3" do
    test "creates a one-time job with required attributes" do
      fire_at = future_time()

      assert {:ok, job} = CronJob.schedule_once("agent-1", ~s({"action":"wake"}), fire_at)
      assert job.agent_id == "agent-1"
      assert job.payload == ~s({"action":"wake"})
      assert job.is_one_time == true
    end

    test "creates a job with is_one_time: false (recurring)" do
      fire_at = future_time()

      assert {:ok, job} =
               CronJob.schedule_once("agent-2", "ping", fire_at, %{is_one_time: false})

      assert job.is_one_time == false
    end

    test "rejects missing agent_id" do
      assert {:error, _} = CronJob.schedule_once(nil, "payload", future_time())
    end

    test "rejects missing payload" do
      assert {:error, _} = CronJob.schedule_once("agent-1", nil, future_time())
    end

    test "rejects missing next_fire_at" do
      assert {:error, _} = CronJob.schedule_once("agent-1", "payload", nil)
    end

    test "defaults is_one_time to true" do
      {:ok, job} = CronJob.schedule_once("agent-check", "payload", future_time())
      assert job.is_one_time == true
    end
  end

  describe "get/1" do
    test "returns job by id" do
      {:ok, created} = CronJob.schedule_once("agent-get", "payload", future_time())
      assert {:ok, fetched} = CronJob.get(created.id)
      assert fetched.id == created.id
    end

    test "returns error for non-existent id" do
      assert {:error, _} = CronJob.get(Ash.UUID.generate())
    end
  end

  describe "for_agent/1" do
    test "returns jobs for a specific agent" do
      {:ok, j1} = CronJob.schedule_once("agent-x", "payload-1", future_time())
      {:ok, j2} = CronJob.schedule_once("agent-x", "payload-2", future_time(7200))
      {:ok, _j3} = CronJob.schedule_once("agent-y", "payload-3", future_time())

      assert {:ok, jobs} = CronJob.for_agent("agent-x")
      ids = Enum.map(jobs, & &1.id)
      assert j1.id in ids
      assert j2.id in ids
      assert length(jobs) == 2
    end

    test "returns empty list when agent has no jobs" do
      assert {:ok, []} = CronJob.for_agent("agent-with-no-jobs")
    end
  end

  describe "all_scheduled/0" do
    test "returns all scheduled jobs sorted by next_fire_at" do
      {:ok, j1} = CronJob.schedule_once("agent-sort", "first", future_time(7200))
      {:ok, j2} = CronJob.schedule_once("agent-sort", "second", future_time(3600))

      assert {:ok, jobs} = CronJob.all_scheduled()
      ids = Enum.map(jobs, & &1.id)
      assert j1.id in ids
      assert j2.id in ids

      # j2 fires sooner, should come first
      relevant = Enum.filter(jobs, &(&1.id in [j1.id, j2.id]))
      assert hd(relevant).id == j2.id
    end
  end

  describe "due/1" do
    test "returns jobs with next_fire_at <= now" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, due_job} = CronJob.schedule_once("agent-due", "fire-me", past_time())
      {:ok, _future_job} = CronJob.schedule_once("agent-due", "not-yet", future_time())

      assert {:ok, due_jobs} = CronJob.due(now)
      ids = Enum.map(due_jobs, & &1.id)
      assert due_job.id in ids
    end

    test "excludes future jobs" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, future_job} = CronJob.schedule_once("agent-future", "not-due", future_time())

      assert {:ok, due_jobs} = CronJob.due(now)
      ids = Enum.map(due_jobs, & &1.id)
      refute future_job.id in ids
    end
  end

  describe "reschedule/2" do
    test "updates next_fire_at" do
      {:ok, job} = CronJob.schedule_once("agent-reschedule", "payload", future_time(3600))
      new_time = future_time(7200)

      assert {:ok, rescheduled} = CronJob.reschedule(job, new_time)
      assert DateTime.truncate(rescheduled.next_fire_at, :second) == new_time
    end
  end

  describe "complete/1 (destroy)" do
    test "deletes the job" do
      {:ok, job} = CronJob.schedule_once("agent-complete", "payload", future_time())

      assert :ok = CronJob.complete(job)
      assert {:error, _} = CronJob.get(job.id)
    end
  end
end
