defmodule Observatory.Gateway.CronSchedulerTest do
  use ExUnit.Case, async: false

  alias Observatory.Gateway.CronScheduler
  alias Observatory.Gateway.CronJob
  alias Observatory.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Clean up any leftover jobs
    Repo.delete_all(CronJob)
    :ok
  end

  describe "schedule_once/3" do
    test "schedules a job with valid params" do
      assert :ok = CronScheduler.schedule_once("agent-1", 5_000, %{"type" => "reminder"})
    end

    test "returns error for negative delay" do
      assert {:error, :invalid_delay} =
               CronScheduler.schedule_once("agent-1", -100, %{"type" => "reminder"})
    end

    test "returns error for zero delay" do
      assert {:error, :invalid_delay} =
               CronScheduler.schedule_once("agent-1", 0, %{"type" => "reminder"})
    end

    test "returns error for non-integer delay" do
      assert {:error, :invalid_delay} =
               CronScheduler.schedule_once("agent-1", 1.5, %{"type" => "reminder"})
    end

    test "returns error for string delay" do
      assert {:error, :invalid_delay} =
               CronScheduler.schedule_once("agent-1", "1000", %{"type" => "reminder"})
    end

    test "persists the job to the database" do
      :ok = CronScheduler.schedule_once("agent-1", 60_000, %{"type" => "reminder"})
      jobs = CronScheduler.list_jobs("agent-1")
      assert length(jobs) == 1
      assert hd(jobs).agent_id == "agent-1"
      assert hd(jobs).is_one_time == true
    end
  end

  describe "job firing and PubSub broadcast" do
    test "fires job and broadcasts to PubSub" do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:test-agent:scheduled")

      :ok = CronScheduler.schedule_once("test-agent", 50, %{"msg" => "hello"})

      assert_receive {:scheduled_job, "test-agent", %{"msg" => "hello"}}, 2_000
    end

    test "deletes one-time job after firing" do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:cleanup-agent:scheduled")

      :ok = CronScheduler.schedule_once("cleanup-agent", 50, %{"type" => "once"})

      assert_receive {:scheduled_job, "cleanup-agent", _payload}, 2_000

      # Give GenServer time to delete
      :timer.sleep(100)

      jobs = CronScheduler.list_jobs("cleanup-agent")
      assert jobs == []
    end
  end

  describe "list_jobs/1" do
    test "returns jobs for the given agent" do
      :ok = CronScheduler.schedule_once("agent-a", 60_000, %{"a" => 1})
      :ok = CronScheduler.schedule_once("agent-b", 60_000, %{"b" => 2})

      assert length(CronScheduler.list_jobs("agent-a")) == 1
      assert length(CronScheduler.list_jobs("agent-b")) == 1
      assert CronScheduler.list_jobs("agent-c") == []
    end
  end

  describe "startup recovery" do
    test "recovers persisted jobs on init" do
      # Use shared mode so the new GenServer can query the DB during init/1
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      Phoenix.PubSub.subscribe(Observatory.PubSub, "agent:recovery-agent:scheduled")

      # Insert a job with a fire time in the near past
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      %CronJob{}
      |> CronJob.changeset(%{
        agent_id: "recovery-agent",
        payload: Jason.encode!(%{"recovered" => true}),
        next_fire_at: DateTime.add(now, -1, :second),
        is_one_time: true
      })
      |> Repo.insert!()

      # Start a second, unregistered scheduler to test init recovery
      {:ok, pid} = GenServer.start(CronScheduler, [])

      # The recovered job should fire immediately (delay <= 0 clamped to 0)
      assert_receive {:scheduled_job, "recovery-agent", %{"recovered" => true}}, 2_000

      GenServer.stop(pid)
    end
  end
end
