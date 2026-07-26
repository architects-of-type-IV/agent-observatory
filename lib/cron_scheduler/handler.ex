defmodule CronScheduler.Handler do
  @moduledoc """
  Behaviour for what actually happens when a job fires.

  In the original system this was an event on a signal bus. Here it is a
  behaviour, so the scheduler carries no opinion about what firing means —
  broadcast it, run it inline, or push it onto another queue.

  Configure with:

      config :cron_scheduler, handler: MyApp.JobHandler

  ## Ordering

  `handle_fire/3` is called *after* the store has been updated — a one-time job
  is already deleted, a recurring one already carries its next fire time. So a
  crash in the handler cannot leave a job firing in a loop, at the cost of the
  handler's own work being lost. If that work matters, make the handler enqueue
  something durable rather than doing it inline.
  """

  alias CronScheduler.Job

  @doc """
  Handle a fired job.

  `payload` is the string the job was scheduled with — decode it yourself if you
  encoded a term. The return value is ignored.
  """
  @callback handle_fire(agent_id :: String.t(), payload :: String.t(), job :: Job.t()) :: any()
end

defmodule CronScheduler.Handler.Noop do
  @moduledoc "Default handler. Fires and does nothing, which is useful for testing the schedule itself."

  @behaviour CronScheduler.Handler

  @impl true
  def handle_fire(_agent_id, _payload, _job), do: :ok
end

defmodule CronScheduler.Handler.ProcessMessage do
  @moduledoc """
  Handler that sends `{:cron_scheduler, :fired, agent_id, payload, job}` to a process.

  Configure the destination as a pid or a registered name:

      config :cron_scheduler,
        handler: CronScheduler.Handler.ProcessMessage,
        handler_target: MyApp.JobListener

  With no `:handler_target` set, nothing is sent.
  """

  @behaviour CronScheduler.Handler

  @impl true
  def handle_fire(agent_id, payload, job) do
    case Application.get_env(:cron_scheduler, :handler_target) do
      nil -> :ok
      target -> send(target, {:cron_scheduler, :fired, agent_id, payload, job})
    end

    :ok
  end
end
