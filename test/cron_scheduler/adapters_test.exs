defmodule CronScheduler.AdaptersTest do
  use ExUnit.Case, async: false

  alias CronScheduler.Job
  alias CronScheduler.Queue
  alias CronScheduler.Store

  setup do
    start_supervised!(Store.ETS)
    :ok
  end

  defp job(attrs \\ []) do
    Job.new(
      Keyword.merge(
        [agent_id: "agent-1", payload: "{}", next_fire_at: DateTime.utc_now()],
        attrs
      )
    )
  end

  describe "Store.ETS" do
    test "insert and get round-trip" do
      {:ok, stored} = Store.ETS.insert(job())

      assert {:ok, found} = Store.ETS.get(stored.id)
      assert found.id == stored.id
      assert found.agent_id == "agent-1"
    end

    test "get reports a missing job" do
      assert {:error, :not_found} = Store.ETS.get("nope")
    end

    test "for_agent filters by agent" do
      {:ok, mine} = Store.ETS.insert(job(agent_id: "mine"))
      {:ok, _} = Store.ETS.insert(job(agent_id: "yours"))

      assert {:ok, [found]} = Store.ETS.for_agent("mine")
      assert found.id == mine.id
    end

    test "all_scheduled sorts soonest first" do
      now = DateTime.utc_now()
      {:ok, later} = Store.ETS.insert(job(next_fire_at: DateTime.add(now, 600, :second)))
      {:ok, sooner} = Store.ETS.insert(job(next_fire_at: DateTime.add(now, 60, :second)))

      assert {:ok, [first, second]} = Store.ETS.all_scheduled()
      assert first.id == sooner.id
      assert second.id == later.id
    end

    test "due includes jobs at the boundary" do
      at = DateTime.add(DateTime.utc_now(), 60, :second)
      {:ok, stored} = Store.ETS.insert(job(next_fire_at: at))

      assert {:ok, [found]} = Store.ETS.due(at)
      assert found.id == stored.id
    end

    test "due excludes jobs still in the future" do
      {:ok, _} = Store.ETS.insert(job(next_fire_at: DateTime.add(DateTime.utc_now(), 600)))

      assert {:ok, []} = Store.ETS.due(DateTime.utc_now())
    end

    test "reschedule moves the fire time and keeps the id" do
      {:ok, stored} = Store.ETS.insert(job())
      later = DateTime.add(DateTime.utc_now(), 600, :second)

      assert {:ok, updated} = Store.ETS.reschedule(stored, later)
      assert updated.id == stored.id
      assert DateTime.compare(updated.next_fire_at, stored.next_fire_at) == :gt

      assert {:ok, reloaded} = Store.ETS.get(stored.id)
      assert DateTime.compare(reloaded.next_fire_at, later) == :eq
    end

    test "complete removes the job and is idempotent" do
      {:ok, stored} = Store.ETS.insert(job())

      assert :ok = Store.ETS.complete(stored)
      assert {:error, :not_found} = Store.ETS.get(stored.id)
      assert :ok = Store.ETS.complete(stored)
    end

    test "implements the Store behaviour" do
      assert behaviours(Store.ETS) |> Enum.member?(CronScheduler.Store)
    end
  end

  describe "Queue.Timer" do
    setup do
      Application.put_env(:cron_scheduler, :store, Store.ETS)
      Application.put_env(:cron_scheduler, :queue, Queue.Timer)
      Application.put_env(:cron_scheduler, :handler, CronScheduler.Handler.ProcessMessage)
      Application.put_env(:cron_scheduler, :handler_target, self())

      start_supervised!(Queue.Timer)

      on_exit(fn ->
        for key <- [:store, :queue, :handler, :handler_target] do
          Application.delete_env(:cron_scheduler, key)
        end
      end)

      :ok
    end

    test "a job scheduled with no delay fires" do
      {:ok, stored} = Store.ETS.insert(job())

      assert :ok = Queue.Timer.enqueue(stored, schedule_in: 0)
      assert_receive {:cron_scheduler, :fired, "agent-1", "{}", _}, 2_000
    end

    test "a pending timer is tracked until it fires" do
      {:ok, stored} = Store.ETS.insert(job())

      :ok = Queue.Timer.enqueue(stored, schedule_in: 30)
      assert stored.id in Queue.Timer.pending()
    end

    test "a duplicate enqueue inside the unique period is dropped" do
      {:ok, stored} = Store.ETS.insert(job())

      :ok = Queue.Timer.enqueue(stored, schedule_in: 30, unique_period: 120)
      :ok = Queue.Timer.enqueue(stored, schedule_in: 30, unique_period: 120)

      assert Enum.count(Queue.Timer.pending(), &(&1 == stored.id)) == 1
    end

    test "a zero unique period allows repeats" do
      {:ok, stored} = Store.ETS.insert(job())

      :ok = Queue.Timer.enqueue(stored, schedule_in: 30, unique_period: 0)
      :ok = Queue.Timer.enqueue(stored, schedule_in: 30, unique_period: 0)

      assert stored.id in Queue.Timer.pending()
    end

    test "clear cancels pending timers" do
      {:ok, stored} = Store.ETS.insert(job())
      :ok = Queue.Timer.enqueue(stored, schedule_in: 30)

      assert :ok = Queue.Timer.clear()
      assert Queue.Timer.pending() == []
    end

    test "end to end: schedule then fire" do
      assert {:ok, _job} = CronScheduler.schedule_once("agent-9", 1, %{action: "now"})

      assert_receive {:cron_scheduler, :fired, "agent-9", payload, _}, 3_000
      assert JSON.decode!(payload) == %{"action" => "now"}
      assert CronScheduler.list_all_jobs() == []
    end

    test "implements the Queue behaviour" do
      assert behaviours(Queue.Timer) |> Enum.member?(CronScheduler.Queue)
    end
  end

  describe "handlers" do
    test "Noop accepts anything" do
      assert CronScheduler.Handler.Noop.handle_fire("a", "{}", job()) == :ok
    end

    test "ProcessMessage with no target configured is not an error" do
      Application.delete_env(:cron_scheduler, :handler_target)

      assert CronScheduler.Handler.ProcessMessage.handle_fire("a", "{}", job()) == :ok
    end
  end

  defp behaviours(module) do
    module.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()
  end
end
