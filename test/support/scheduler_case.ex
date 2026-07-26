defmodule CronScheduler.SchedulerCase do
  @moduledoc """
  Test case wiring the scheduler to the ETS store and a recording queue.

  The recording queue keeps tests off real timers: they assert on what was
  enqueued and call `CronScheduler.fire/1` directly. Timer behaviour is covered
  separately in its own test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias CronScheduler.Test.RecordingQueue
      import CronScheduler.SchedulerCase
    end
  end

  setup tags do
    put_config(:store, tags[:store] || CronScheduler.Store.ETS)
    put_config(:queue, tags[:queue] || CronScheduler.Test.RecordingQueue)
    put_config(:handler, tags[:handler] || CronScheduler.Handler.ProcessMessage)
    put_config(:handler_target, self())

    start_supervised!(CronScheduler.Store.ETS)
    :ok = CronScheduler.Test.RecordingQueue.setup()

    on_exit(fn ->
      for key <- [:store, :queue, :handler, :handler_target, :default_interval_ms] do
        Application.delete_env(:cron_scheduler, key)
      end
    end)

    :ok
  end

  @doc "Set a `:cron_scheduler` config key for the duration of the test."
  def put_config(key, value), do: Application.put_env(:cron_scheduler, key, value)
end
