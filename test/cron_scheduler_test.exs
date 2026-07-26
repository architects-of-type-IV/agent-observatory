defmodule CronSchedulerTest do
  use CronScheduler.SchedulerCase

  alias CronScheduler.Job

  describe "schedule_once/3" do
    test "stores the job and enqueues it" do
      assert {:ok, job} = CronScheduler.schedule_once("agent-1", 60_000, %{action: "ping"})

      assert job.agent_id == "agent-1"
      assert job.is_one_time
      assert [{enqueued, opts}] = RecordingQueue.enqueues()
      assert enqueued.id == job.id
      assert opts[:schedule_in] == 60
    end

    test "encodes a map payload as JSON" do
      {:ok, job} = CronScheduler.schedule_once("agent-1", 1_000, %{action: "ping", n: 1})

      assert JSON.decode!(job.payload) == %{"action" => "ping", "n" => 1}
    end

    test "passes a string payload through untouched" do
      {:ok, job} = CronScheduler.schedule_once("agent-1", 1_000, "raw text")

      assert job.payload == "raw text"
    end

    test "sets next_fire_at from the delay" do
      {:ok, job} = CronScheduler.schedule_once("agent-1", 60_000, %{})

      assert DateTime.diff(job.next_fire_at, DateTime.utc_now()) in 58..60
    end

    test "carries a unique period so recovery cannot double-enqueue" do
      {:ok, _} = CronScheduler.schedule_once("agent-1", 1_000, %{})

      assert [{_job, opts}] = RecordingQueue.enqueues()
      assert opts[:unique_period] > 0
    end

    test "rejects a non-positive delay without touching the store" do
      assert {:error, :invalid_delay} = CronScheduler.schedule_once("agent-1", 0, %{})
      assert {:error, :invalid_delay} = CronScheduler.schedule_once("agent-1", -5, %{})

      assert CronScheduler.list_all_jobs() == []
      assert RecordingQueue.enqueues() == []
    end

    test "rejects a non-integer delay" do
      assert {:error, :invalid_delay} = CronScheduler.schedule_once("agent-1", "soon", %{})
    end

    @tag store: CronScheduler.Test.FailingStore
    test "reports a store failure" do
      assert {:error, :insert_failed} = CronScheduler.schedule_once("agent-1", 1_000, %{})
    end

    @tag queue: CronScheduler.Test.FailingQueue
    test "rolls the store record back when the queue refuses" do
      assert {:error, :insert_failed} = CronScheduler.schedule_once("agent-1", 1_000, %{})

      # The critical part: nothing left scheduled that no timer will ever wake.
      assert CronScheduler.list_all_jobs() == []
    end
  end

  describe "schedule_recurring/3" do
    test "stores a recurring job carrying its interval" do
      assert {:ok, job} = CronScheduler.schedule_recurring("agent-1", 300_000, %{action: "poll"})

      refute job.is_one_time
      assert job.interval_ms == 300_000
    end

    test "enqueues at the interval" do
      {:ok, _} = CronScheduler.schedule_recurring("agent-1", 300_000, %{})

      assert [{_job, opts}] = RecordingQueue.enqueues()
      assert opts[:schedule_in] == 300
    end
  end

  describe "list_jobs/1 and list_all_jobs/0" do
    test "list_jobs returns only that agent's jobs" do
      {:ok, a} = CronScheduler.schedule_once("agent-1", 1_000, %{})
      {:ok, _} = CronScheduler.schedule_once("agent-2", 1_000, %{})

      assert [job] = CronScheduler.list_jobs("agent-1")
      assert job.id == a.id
    end

    test "list_jobs is empty for an unknown agent" do
      assert CronScheduler.list_jobs("nobody") == []
    end

    test "list_all_jobs returns every job soonest first" do
      {:ok, later} = CronScheduler.schedule_once("agent-1", 600_000, %{})
      {:ok, sooner} = CronScheduler.schedule_once("agent-1", 1_000, %{})

      assert [first, second] = CronScheduler.list_all_jobs()
      assert first.id == sooner.id
      assert second.id == later.id
    end

    @tag store: CronScheduler.Test.FailingStore
    test "a store failure yields an empty list rather than raising" do
      assert CronScheduler.list_all_jobs() == []
      assert CronScheduler.list_jobs("agent-1") == []
      assert CronScheduler.due_jobs() == []
    end
  end

  describe "due_jobs/1" do
    test "returns only jobs at or before the given time" do
      {:ok, soon} = CronScheduler.schedule_once("agent-1", 1_000, %{})
      {:ok, _far} = CronScheduler.schedule_once("agent-1", 600_000, %{})

      due = CronScheduler.due_jobs(DateTime.add(DateTime.utc_now(), 60, :second))

      assert Enum.map(due, & &1.id) == [soon.id]
    end

    test "is empty when nothing is due yet" do
      {:ok, _} = CronScheduler.schedule_once("agent-1", 600_000, %{})

      assert CronScheduler.due_jobs() == []
    end
  end

  describe "cancel/1" do
    test "removes the job" do
      {:ok, job} = CronScheduler.schedule_once("agent-1", 60_000, %{})

      assert :ok = CronScheduler.cancel(job.id)
      assert CronScheduler.list_all_jobs() == []
    end

    test "succeeds for an unknown id" do
      assert :ok = CronScheduler.cancel("no-such-job")
    end

    test "a cancelled job that still fires is a no-op" do
      {:ok, job} = CronScheduler.schedule_once("agent-1", 60_000, %{})
      :ok = CronScheduler.cancel(job.id)

      assert :ok = CronScheduler.fire(job.id)
      refute_receive {:cron_scheduler, :fired, _, _, _}, 50
    end
  end

  describe "fire/1 for a one-time job" do
    setup do
      {:ok, job} = CronScheduler.schedule_once("agent-1", 60_000, %{action: "ping"})
      {:ok, job: job}
    end

    test "calls the handler with the agent and payload", %{job: job} do
      assert :ok = CronScheduler.fire(job.id)

      assert_receive {:cron_scheduler, :fired, "agent-1", payload, fired}
      assert JSON.decode!(payload) == %{"action" => "ping"}
      assert fired.id == job.id
    end

    test "removes the job from the store", %{job: job} do
      :ok = CronScheduler.fire(job.id)

      assert CronScheduler.list_all_jobs() == []
    end

    test "does not re-enqueue", %{job: job} do
      :ok = CronScheduler.fire(job.id)

      assert RecordingQueue.enqueues_for(job.id) |> length() == 1
    end

    test "firing twice only fires the handler once", %{job: job} do
      :ok = CronScheduler.fire(job.id)
      assert_receive {:cron_scheduler, :fired, _, _, _}

      assert :ok = CronScheduler.fire(job.id)
      refute_receive {:cron_scheduler, :fired, _, _, _}, 50
    end
  end

  describe "fire/1 for a recurring job" do
    setup do
      {:ok, job} = CronScheduler.schedule_recurring("agent-1", 300_000, %{action: "poll"})
      {:ok, job: job}
    end

    test "calls the handler", %{job: job} do
      assert :ok = CronScheduler.fire(job.id)

      assert_receive {:cron_scheduler, :fired, "agent-1", _payload, fired}
      assert fired.id == job.id
    end

    test "keeps the job and sets the next fire an interval out", %{job: job} do
      :ok = CronScheduler.fire(job.id)

      assert [rescheduled] = CronScheduler.list_all_jobs()
      assert rescheduled.id == job.id
      assert DateTime.diff(rescheduled.next_fire_at, DateTime.utc_now()) in 298..300
    end

    test "an overdue job is moved forward, not left in the past" do
      {:ok, overdue} =
        CronScheduler.Store.ETS.insert(
          Job.new(
            agent_id: "agent-3",
            payload: "{}",
            next_fire_at: DateTime.add(DateTime.utc_now(), -3_600, :second),
            is_one_time: false,
            interval_ms: 300_000
          )
        )

      :ok = CronScheduler.fire(overdue.id)

      assert [rescheduled] = CronScheduler.list_jobs("agent-3")
      assert DateTime.compare(rescheduled.next_fire_at, overdue.next_fire_at) == :gt
      assert DateTime.compare(rescheduled.next_fire_at, DateTime.utc_now()) == :gt
    end

    test "re-enqueues at the interval", %{job: job} do
      :ok = CronScheduler.fire(job.id)

      assert [_first, {_job, opts}] = RecordingQueue.enqueues_for(job.id)
      assert opts[:schedule_in] == 300
    end

    test "fires repeatedly", %{job: job} do
      for _ <- 1..3 do
        assert :ok = CronScheduler.fire(job.id)
        assert_receive {:cron_scheduler, :fired, _, _, _}
      end

      assert [_] = CronScheduler.list_all_jobs()
    end

    test "falls back to the configured default interval when the job has none" do
      put_config(:default_interval_ms, 120_000)

      {:ok, stored} =
        CronScheduler.Store.ETS.insert(
          Job.new(
            agent_id: "agent-2",
            payload: "{}",
            next_fire_at: DateTime.utc_now(),
            is_one_time: false
          )
        )

      assert :ok = CronScheduler.fire(stored.id)

      assert [{_job, opts}] = RecordingQueue.enqueues_for(stored.id)
      assert opts[:schedule_in] == 120
    end
  end

  describe "fire/1 edge cases" do
    test "an unknown id is a no-op" do
      assert :ok = CronScheduler.fire("no-such-job")
    end

    @tag store: CronScheduler.Test.FailingStore
    test "a store failure is reported" do
      assert {:error, :store_down} = CronScheduler.fire("anything")
    end
  end

  describe "recover_jobs/0" do
    test "re-enqueues every stored job" do
      {:ok, a} = CronScheduler.schedule_once("agent-1", 60_000, %{})
      {:ok, b} = CronScheduler.schedule_once("agent-2", 60_000, %{})
      :ok = RecordingQueue.setup()

      assert :ok = CronScheduler.recover_jobs()

      ids = RecordingQueue.enqueues() |> Enum.map(fn {job, _} -> job.id end) |> Enum.sort()
      assert ids == Enum.sort([a.id, b.id])
    end

    test "enqueues an overdue job with no delay rather than a negative one" do
      {:ok, stored} =
        CronScheduler.Store.ETS.insert(
          Job.new(
            agent_id: "agent-1",
            payload: "{}",
            next_fire_at: DateTime.add(DateTime.utc_now(), -3_600, :second)
          )
        )

      :ok = RecordingQueue.setup()
      assert :ok = CronScheduler.recover_jobs()

      assert [{job, opts}] = RecordingQueue.enqueues()
      assert job.id == stored.id
      assert opts[:schedule_in] == 0
    end

    test "preserves the remaining delay for a future job" do
      {:ok, _} = CronScheduler.schedule_once("agent-1", 600_000, %{})
      :ok = RecordingQueue.setup()

      :ok = CronScheduler.recover_jobs()

      assert [{_job, opts}] = RecordingQueue.enqueues()
      assert opts[:schedule_in] in 598..600
    end

    test "is a no-op with nothing stored" do
      assert :ok = CronScheduler.recover_jobs()
      assert RecordingQueue.enqueues() == []
    end

    @tag queue: CronScheduler.Test.FailingQueue
    test "a queue failure does not stop the remaining jobs" do
      put_config(:queue, CronScheduler.Test.RecordingQueue)
      {:ok, _} = CronScheduler.schedule_once("agent-1", 60_000, %{})
      {:ok, _} = CronScheduler.schedule_once("agent-2", 60_000, %{})

      put_config(:queue, CronScheduler.Test.FailingQueue)
      assert :ok = CronScheduler.recover_jobs()
    end
  end

  describe "encode_payload/1" do
    test "passes strings through" do
      assert CronScheduler.encode_payload("already a string") == "already a string"
    end

    test "encodes maps, lists, and numbers" do
      assert CronScheduler.encode_payload(%{a: 1}) == ~s({"a":1})
      assert CronScheduler.encode_payload([1, 2]) == "[1,2]"
      assert CronScheduler.encode_payload(42) == "42"
    end
  end

  describe "missing configuration" do
    test "raises a message naming the key and the bundled default" do
      Application.delete_env(:cron_scheduler, :store)

      assert_raise ArgumentError, ~r/CronScheduler needs a store/, fn ->
        CronScheduler.list_all_jobs()
      end
    end
  end
end
