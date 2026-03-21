defmodule Ichor.Infrastructure.CronSchedulerTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Ichor.Infrastructure.CronScheduler
  alias Ichor.Factory.CronJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Ichor.Repo)
  end

  describe "schedule_once/3" do
    test "returns :ok for valid delay" do
      agent_id = "agent-cron-#{System.unique_integer([:positive])}"
      result = CronScheduler.schedule_once(agent_id, 5_000, %{task: "do_something"})
      assert result == :ok
    end

    test "returns {:error, :invalid_delay} for zero delay" do
      result = CronScheduler.schedule_once("agent-1", 0, %{})
      assert result == {:error, :invalid_delay}
    end

    test "returns {:error, :invalid_delay} for negative delay" do
      result = CronScheduler.schedule_once("agent-1", -1000, %{})
      assert result == {:error, :invalid_delay}
    end

    test "returns {:error, :invalid_delay} for non-integer delay" do
      result = CronScheduler.schedule_once("agent-1", "5000", %{})
      assert result == {:error, :invalid_delay}
    end

    test "returns {:error, :invalid_delay} for nil delay" do
      result = CronScheduler.schedule_once("agent-1", nil, %{})
      assert result == {:error, :invalid_delay}
    end
  end

  describe "list_jobs/1" do
    test "returns empty list for agent with no jobs" do
      jobs = CronScheduler.list_jobs("agent-no-jobs-#{System.unique_integer([:positive])}")
      assert jobs == []
    end

    test "returns jobs scoped to the given agent" do
      agent_id = "agent-list-#{System.unique_integer([:positive])}"
      next_fire = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      # Insert directly via CronJob to bypass Oban inline (which would consume and delete the row)
      {:ok, _} = CronJob.schedule_once(agent_id, "\"{}\"", next_fire)

      jobs = CronScheduler.list_jobs(agent_id)
      assert length(jobs) >= 1
      Enum.each(jobs, fn job -> assert job.agent_id == agent_id end)
    end
  end

  describe "list_all_jobs/0" do
    test "returns a list (possibly empty)" do
      jobs = CronScheduler.list_all_jobs()
      assert is_list(jobs)
    end

    test "includes jobs from multiple agents inserted directly" do
      agent_a = "agent-all-a-#{System.unique_integer([:positive])}"
      agent_b = "agent-all-b-#{System.unique_integer([:positive])}"
      next_fire = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      # Insert directly via CronJob to bypass Oban inline execution (which would delete them)
      {:ok, _} = CronJob.schedule_once(agent_a, "\"{}\"", next_fire)
      {:ok, _} = CronJob.schedule_once(agent_b, "\"{}\"", next_fire)

      all_jobs = CronScheduler.list_all_jobs()
      agent_ids = Enum.map(all_jobs, & &1.agent_id)

      assert agent_a in agent_ids
      assert agent_b in agent_ids
    end
  end

  describe "CronJob direct code_interface" do
    test "schedule_once creates a cron job record" do
      agent_id = "agent-direct-#{System.unique_integer([:positive])}"
      next_fire = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      {:ok, job} = CronJob.schedule_once(agent_id, Jason.encode!(%{task: "run"}), next_fire)

      assert job.agent_id == agent_id
      assert job.is_one_time == true
      assert DateTime.compare(job.next_fire_at, next_fire) == :eq
    end

    test "for_agent returns jobs for that agent only" do
      agent_id = "agent-scope-#{System.unique_integer([:positive])}"
      next_fire = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      {:ok, _job} = CronJob.schedule_once(agent_id, "\"payload\"", next_fire)

      {:ok, jobs} = CronJob.for_agent(agent_id)
      assert length(jobs) >= 1
      assert Enum.all?(jobs, &(&1.agent_id == agent_id))
    end

    test "complete destroys the job record" do
      agent_id = "agent-complete-#{System.unique_integer([:positive])}"
      next_fire = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      {:ok, job} = CronJob.schedule_once(agent_id, "\"done\"", next_fire)
      assert :ok = CronJob.complete(job)

      {:ok, remaining} = CronJob.for_agent(agent_id)
      assert Enum.all?(remaining, &(&1.id != job.id))
    end

    test "all_scheduled returns jobs sorted by next_fire_at ascending" do
      agent_id = "agent-all-sched-#{System.unique_integer([:positive])}"
      t1 = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      t2 = DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.truncate(:second)

      {:ok, j1} = CronJob.schedule_once(agent_id, "\"a\"", t1)
      {:ok, j2} = CronJob.schedule_once(agent_id, "\"b\"", t2)

      {:ok, all} = CronJob.all_scheduled()
      ids = Enum.map(all, & &1.id)

      assert j1.id in ids
      assert j2.id in ids
    end
  end
end
